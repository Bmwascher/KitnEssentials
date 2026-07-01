-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Window.lua                                  ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Per-window frame tree + create-once bar pool.  ║
-- ║           Frame construction ONLY -- the render/update   ║
-- ║           path (secret-safe SetValue + text gating) is   ║
-- ║           built in the next chunk. Each window is a      ║
-- ║           header + scroll viewport + content child, with ║
-- ║           BAR_POOL_SIZE bars pre-acquired once and laid  ║
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
local Ambiguate = Ambiguate
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil

-- Sticky GUID -> display-name memo for the ShowRealm path. The C_DamageMeter source
-- name resolves to "Name-Realm" while the unit is fully known but intermittently
-- falls back to bare "Name" (observed across phase transitions), so rendering it
-- verbatim makes the realm suffix flicker. Keyed on the per-character-immutable
-- sourceGUID (issecretvalue-guarded at use, so a secret guid is simply skipped --
-- never indexed), this remembers the realm-bearing form and refuses to DOWNGRADE: once a
-- cross-realm member has shown its realm we keep it on the ticks the API drops it.
-- A same-realm name has no hyphen so it's never stored. Grows by at most one tiny
-- entry per distinct cross-realm player seen (bounded by group size; wiped on
-- /reload), so it needs no eviction. Some meters sidestep all this by always stripping
-- the realm (Ambiguate "short"); ShowRealm is a KE-only feature, hence a KE-only memo.
local realmNames = {}

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

-- Anchor a bar's StatusBar fill: the full row (normal) or a thin strip pinned to the
-- row's bottom edge (BarThinLine mode). Thin-line keeps the row's icon + text at full
-- size -- they anchor to the row, NOT the fill (see MakeBar / the RenderBar layout
-- block), so a thin fill leaves them untouched -- and shrinks only the colored fill into
-- a clean underline. snapHeight is the pixel-snapped row height; the strip is clamped to
-- [1, snapHeight]. Plain numbers / SetPoint only -- never a secret. Called from
-- CreateWindow's build loop and ApplyWindowGeometry (both user/structural, not per tick).
local function ApplyFillGeometry(row, db, snapHeight)
    row.fill:ClearAllPoints()
    if db and db.BarThinLine then
        local thinH = KE:PixelSnap((db and db.BarThinLineHeight) or 2)
        if thinH < 1 then thinH = 1 end
        if snapHeight and thinH > snapHeight then thinH = snapHeight end
        row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.fill:SetHeight(thinH)
    else
        row.fill:SetAllPoints(row)
    end
end

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
    -- layer; safe to concatenate even when secret). Anchored to the ROW (not row.fill)
    -- for vertical centering so it stays full-height-centered in BarThinLine mode (where
    -- the fill is only a bottom strip); identical to row.fill in normal mode (fill ==
    -- row), so this is a no-op for the default look.
    row.value = row.fill:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row, "RIGHT", -3, 0)
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
    --   _rawName          -- last plain (non-secret) name BEFORE the realm strip; nil
    --                        while secret. The Detail Targets sub-section keys its
    --                        per-player lookup on this unstripped name (the targets
    --                        map is keyed on the raw det.unitName, which carries the
    --                        "-Realm" suffix for cross-realm members) -- _cachedName
    --                        loses the suffix when ShowRealm is off and would miss.
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
    bar._rawName = nil
    bar._cachedVal = nil
    bar._cachedValColorTbl = nil   -- last db.BarTextColor table ref applied to row.value (value-color dirty key)
    bar._cachedSlot = nil
    bar._layoutKey = nil
    bar._iconShown = false
    bar._nameShown = nil
    bar._rankShown = nil
    bar._sourceGUID = nil
    bar._sourceCreatureID = nil
    bar._deathRecapID = nil
    bar._classFilename = nil

    -- Wire OnClick ONCE. Left-click opens the per-source detail panel; right-click
    -- routes to the window dispatcher (close detail / toggle the view selector,
    -- Selector.lua). Both DM methods resolve at runtime (Detail.lua / Selector.lua
    -- load after this file), so each call is guarded.
    row:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if DM.OnWindowRightClick then DM:OnWindowRightClick(bar.win) end
        elseif DM.OpenDetail then
            DM:OpenDetail(bar, button)
        end
    end)

    -- Hover quick-peek (Phase 4b / Task 9). Forward-resolved like OnClick above
    -- (Detail.lua defines ShowHoverTip / HideHoverTip and loads after Window.lua).
    -- bar.win is assigned where the pool is built in CreateWindow; the methods
    -- guard against a missing window themselves. The populate path is OOC-gated
    -- for secret reads and shows a "secret while in combat" message in combat.
    row:SetScript("OnEnter", function()
        if DM.ShowHoverTip then DM:ShowHoverTip(bar.win, bar, true) end  -- isInitial: anchor the tip once on hover
    end)
    row:SetScript("OnLeave", function()
        if DM.HideHoverTip then DM:HideHoverTip() end
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

    -- Header meter-type glyph (left of the title). The render layer assigns its texture
    -- from the live MeterType (self.METER_TYPE_ICONS); its size tracks the header font in
    -- LayoutWindow. The title FontString anchors to its right so they read as one
    -- "[icon] Label" unit. Hidden until the first RenderWindow assigns a type.
    W.headerIcon = W.frame:CreateTexture(nil, "OVERLAY")
    W.headerIcon:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 4, -2)
    W.headerIcon:Hide()

    -- Header title FontString. The render layer sets the live text. Sized by the
    -- HeaderFontSize override, which falls back to the shared FontSize when unset -- so an
    -- existing config keeps its current header size until the new Header Text Size slider
    -- is touched (the bar text stays on FontSize). The anchor is re-set authoritatively by
    -- RenderWindow (to the icon's right, or flush-left when the type has no glyph).
    W.header = W.frame:CreateFontString(nil, "OVERLAY")
    W.header:SetPoint("LEFT", W.headerIcon, "RIGHT", 3, 0)
    W.header:SetJustifyH("LEFT")
    KE:ApplyFontToText(
        W.header,
        self.db and self.db.FontFace,
        self.db and ((self.db.HeaderFontSize or self.db.FontSize) or 12),
        self.db and self.db.FontOutline
    )

    -- Header hover region: a full-width strip over the whole header band (title -> icons).
    -- ApplyHeaderIcons wires its OnEnter/OnLeave to drive the mouseover-reveal, so hovering
    -- ANYWHERE on the header reveals/holds the icons as one consistent zone (the icons,
    -- being children, would otherwise each steal focus and flicker the reveal). It only
    -- needs motion, so clicks propagate through and it never blocks the EditMode mover or
    -- anything below. Height is kept in sync with the header band in LayoutWindow. Also the
    -- clean seam for a future header-bar coloring/backdrop. Mouse is enabled on demand by
    -- ApplyHeaderIcons (mouseover mode only) and released otherwise -- no capture leak.
    W.headerBar = CreateFrame("Frame", nil, W.frame)
    W.headerBar:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, 0)
    W.headerBar:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", 0, 0)
    W.headerBar:SetHeight(18)
    W.headerBar:SetFrameLevel(W.frame:GetFrameLevel() + 1)
    W.headerBar:EnableMouse(false)
    if W.headerBar.SetPropagateMouseClicks then
        W.headerBar:SetPropagateMouseClicks(true)
    end

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

    -- Phase 4 header icons: settings / reset / segment / report, right-aligned,
    -- stepping left from the frame's TOPRIGHT (report furthest left). Built once here
    -- (the pool-build below never re-runs); visibility is driven by db.ShowHeaderIcons
    -- (Task 7). The frame level
    -- is bumped above the bars so the icons stay clickable over the body rows. The
    -- callbacks resolve DM methods at click time (Core.lua defines them), matching
    -- the runtime-resolve pattern used by the OnClick -> DM:OpenDetail hook above.
    local function MakeHeaderBtn(tex, tooltip, onClick, xStep, size)
        size = size or 12
        local b = CreateFrame("Button", nil, W.frame)
        b:SetSize(size, size)
        -- Right edges stay on the 18px step grid; a larger icon (report) grows LEFT into
        -- its own empty slot and rises by half the size delta from the 12px baseline
        -- (top -4) so every icon shares one vertical center line.
        b:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -2 - xStep, -4 - ((12 - size) / 2))
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
            DM:RevealHeaderIcons(W)
        end)
        b:SetScript("OnLeave", function(btn)
            btn.icon:SetVertexColor(0.8, 0.8, 0.8)
            GameTooltip:Hide()
            DM:HeaderIconLeave(W)
        end)
        b:SetScript("OnClick", onClick)
        return b
    end

    W.headerBtns = {}
    W.headerBtns.settings = MakeHeaderBtn("Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_settings.tga",
        "Settings", function() DM:HeaderSettings(W) end, 0)
    W.headerBtns.reset = MakeHeaderBtn("Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_reset.tga",
        "Reset", function() DM:HeaderReset(W) end, 18)
    W.headerBtns.segment = MakeHeaderBtn("Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_segment.tga",
        "Segment", function() DM:ToggleSegmentMenu(W) end, 36)
    -- Report sits just left of segment (xStep 50, ~2px gap) and is larger (18px) than the
    -- 12px action icons. Clicking it opens a channel picker (DM:OpenReportMenu) that reports
    -- THIS window's view to the chosen chat channel.
    W.headerBtns.report = MakeHeaderBtn("Interface\\AddOns\\KitnEssentials\\Media\\Icon\\dm_report.blp",
        "Report", function() DM:OpenReportMenu(W) end, 50, 18)

    -- The ⌚ segment button opens its picker on HOVER (quick adjust) rather than only on
    -- click -- the custom dropdown (SegmentMenu.lua) IS the content, so it replaces the
    -- generic "Segment" tooltip while keeping the icon brighten. Leaving the icon
    -- schedules a grace close so the cursor can travel up onto the panel. The OnClick
    -- toggle (set by MakeHeaderBtn) still works as a deliberate open/close affordance.
    do
        local seg = W.headerBtns.segment
        seg:SetScript("OnEnter", function(btn)
            btn.icon:SetVertexColor(1, 1, 1)
            DM:RevealHeaderIcons(W)
            if DM.OpenSegmentMenu then DM:OpenSegmentMenu(W) end
        end)
        seg:SetScript("OnLeave", function(btn)
            btn.icon:SetVertexColor(0.8, 0.8, 0.8)
            DM:HeaderIconLeave(W)
            if DM.ScheduleSegmentClose then DM:ScheduleSegmentClose(W) end
        end)
    end

    -- Apply the initial header-icon visibility / mouseover state from the DB
    -- (Task 7). ApplyHeaderIcons is idempotent and is also re-run from
    -- ReapplyBarVisuals so a live GUI toggle takes effect without a /reload.
    self:ApplyHeaderIcons(W)

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

    -- Right-click the bar box (the body) to open the view selector (Selector.lua).
    -- W.body IS the box where bars load; it is hidden whenever the detail/selector
    -- overlay is open, so it never conflicts with their own click handling. Bars sit
    -- above it and keep their own clicks; an empty-space right-click falls to here.
    -- SetPropagateMouseMotion is retained (harmless) but no longer drives the header
    -- reveal -- that moved to the dedicated W.headerBar region, scoped to the header
    -- strip. DM:OnWindowRightClick is resolved at runtime (Selector.lua loads later).
    W.body:EnableMouse(true)
    if W.body.SetPropagateMouseMotion then
        W.body:SetPropagateMouseMotion(true)
    end
    W.body:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and DM.OnWindowRightClick then
            DM:OnWindowRightClick(W)
        end
    end)

    -- Mouse-wheel scroll. A short pane (e.g. a 35%-height stacked window) shows fewer
    -- rows than the meter holds, so the wheel scrolls the bar list to reach the
    -- overflow. The native ScrollFrame clips the content child to the body rect, so a
    -- partially-visible bottom row is cut cleanly at the body edge (no bleed into the
    -- next stacked window). One bar (stride) per notch. The max is stashed on W by
    -- RenderWindow each tick (W._scrollMax = rendered height - viewport height) so it
    -- tracks the live bar count: 0 when everything fits, making the wheel a no-op.
    -- Same convention as the Selector overlay's wheel handler.
    W.body:EnableMouseWheel(true)
    W.body:SetScript("OnMouseWheel", function(self2, delta)
        local maxS = W._scrollMax or 0
        if maxS <= 0 then self2:SetVerticalScroll(0); return end
        local stride = W._snapStride or 1
        if stride <= 0 then stride = 1 end
        local new = (self2:GetVerticalScroll() or 0) - delta * stride
        if new < 0 then new = 0 elseif new > maxS then new = maxS end
        self2:SetVerticalScroll(new)
        -- Re-render this window so rows revealed by the scroll get filled. With viewport
        -- culling (RenderWindow) only the in-view rows are rendered each tick, so a row
        -- scrolled into view would be blank/stale without this. RenderWindow re-reads the
        -- new scroll offset to recompute which slots are visible; the session read it does
        -- is pcall'd + secret-safe, so calling it outside the ticker is fine.
        if DM.RenderWindow then DM:RenderWindow(W) end
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

        -- Fill anchor: full row, or a thin bottom strip in BarThinLine mode.
        ApplyFillGeometry(row, self.db, snapHeight)

        -- rank/name anchor left after the icon; resolved fully in the render
        -- chunk (which knows ShowIcon/ShowRank). Provide a sane default anchor
        -- so the row is laid out even before first render. Anchored to the ROW (not
        -- row.fill) so vertical centering holds in BarThinLine mode; identical in
        -- normal mode (fill == row).
        row.rank:ClearAllPoints()
        row.rank:SetPoint("LEFT", row, "LEFT", 3, 0)
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
    -- The header band + meter-type glyph track the HEADER font size (the per-header
    -- override, falling back to the shared FontSize when unset). Bar TEXT size (FontSize)
    -- drives row layout via the snapped stride, not this band.
    local headerFontSize = (db and (db.HeaderFontSize or db.FontSize)) or 12
    local visibleDB = (db and db.VisibleBars) or 10
    local stride = W._snapStride or 1

    -- Input-identity short-circuit. The header band derives ONLY from HeaderFontSize, and
    -- the content height from VisibleBars + the snapped stride -- all plain numbers, never
    -- secret. RenderWindow calls this every tick; when none of those changed the
    -- PixelSnap / min / multiply below reproduce the identical result, so skip them.
    -- ApplyWindowGeometry updates _snapStride before calling here, so keying on it
    -- keeps a bar-size change from being short-circuited away.
    if W._lwHeaderFontSize == headerFontSize and W._lwVisibleBars == visibleDB and W._lwStride == stride then
        return
    end
    W._lwHeaderFontSize, W._lwVisibleBars, W._lwStride = headerFontSize, visibleDB, stride

    -- Fixed header band (header-font-size driven, snapped). The header FontString is
    -- anchored TOPLEFT inside this band; the body starts immediately below it.
    local headerH = KE:PixelSnap(headerFontSize + 6)

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
        -- Keep the header hover region spanning exactly the header band.
        if W.headerBar then W.headerBar:SetHeight(headerH) end
        -- The meter-type glyph sits a bit larger than the header text and is vertically
        -- centered in the band -- anchored to the header strip (W.headerBar spans exactly
        -- the band), so it tracks the band height without any manual offset math.
        if W.headerIcon and W.headerBar then
            local iconSize = headerFontSize + 4
            W.headerIcon:SetSize(iconSize, iconSize)
            W.headerIcon:ClearAllPoints()
            W.headerIcon:SetPoint("LEFT", W.headerBar, "LEFT", 4, 0)
        end
        -- The detail panel covers the same area as the body; keep its top edge in
        -- sync with the header band. Its anchor was baked at EnsureDetail time, so a
        -- later font-size change would otherwise leave a gap/overlap on the next open.
        if W.detail then
            W.detail:ClearAllPoints()
            W.detail:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -headerH)
            W.detail:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)
        end
        -- The view-selector overlay (Selector.lua) covers the same body area; keep it
        -- in sync with the header band too (its anchor was baked at EnsureSelector time).
        if W.selector then
            W.selector:ClearAllPoints()
            W.selector:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -headerH)
            W.selector:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Content HEIGHT only (the dock owns the width; the body's OnSizeChanged
    -- handler keeps the width synced). Set on actual change so the steady state
    -- does no per-tick SetHeight. This is the BASE height (VisibleBars rows);
    -- RenderWindow grows the scroll child over it when the rendered list
    -- overflows the viewport -- nil its cache so the next render re-applies
    -- against the new base instead of skipping on a stale match.
    if W._contentH ~= barsH then
        W._contentH = barsH
        W.content:SetHeight(barsH)
        W._renderContentH = nil
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

    -- Re-apply each bar's fill geometry (full row vs thin-line bottom strip) on every
    -- settings apply: BarThinLine / BarThinLineHeight can toggle without snapHeight
    -- changing, so this isn't covered by the dirty-gate above. Cheap (user-driven, not
    -- per tick); snapHeight is the live snapped row height clamp for the strip.
    for i = 1, BAR_POOL_SIZE do
        ApplyFillGeometry(W.bars[i].row, db, snapHeight)
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
    -- Header text has its own size (falls back to the bar FontSize when the override is
    -- unset); bars/detail/selector keep `size`. LayoutWindow re-sizes the header glyph.
    local headerSize = db and ((db.HeaderFontSize or db.FontSize) or 12)
    local outline = db and db.FontOutline
    local texPath = KE:GetStatusbarPath(db and db.StatusBarTexture or "KitnUI")

    KE:ApplyFontToText(W.header, face, headerSize, outline)
    -- Force RenderWindow's header block to rebuild next tick so a live GUI change to
    -- ShowTypeIcon (or the header font) re-evaluates the meter-type glyph + title anchor --
    -- that block is otherwise dirty-gated on meter/session type, which a toggle doesn't move.
    W._headerType = nil
    for i = 1, BAR_POOL_SIZE do
        local bar = W.bars[i]
        local row = bar.row
        row.fill:SetStatusBarTexture(texPath)
        KE:ApplyFontToText(row.rank, face, size, outline)
        KE:ApplyFontToText(row.name, face, size, outline)
        KE:ApplyFontToText(row.value, face, size, outline)
        -- Drop the per-bar color dirty caches so the next Tick repaints fill / name / value
        -- color with the live BarColorMode / BarColor / BarColorAlpha / BarTextColor (all
        -- GUI-only -- the per-attribute caches in RenderBar wouldn't otherwise notice). The
        -- value-color nil also matters because ApplyFontToText above resets the FontString
        -- color, so RenderBar must re-apply BarTextColor on the next tick.
        bar._cachedColorClass = nil
        bar._cachedNameColorClass = nil
        bar._cachedNameColorOn = nil
        bar._cachedValColorTbl = nil
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

    -- Selector cards (Selector.lua) absorb the same live font change. Lazy-built, so
    -- this is a no-op until the user first opens the selector for this window.
    if W.selector and W.selector.cards then
        local cardSize = math_max(8, (size or 12) - 2)
        for _, card in ipairs(W.selector.cards) do
            KE:ApplyFontToText(card.label, face, cardSize, outline)
        end
    end

    -- Segment-menu rows (SegmentMenu.lua) likewise. Pooled + lazy-built, so this is a
    -- no-op until the ⌚ picker has been opened once for this window.
    if W.segMenu and W.segMenu.rows then
        local rowSize = math_max(8, (size or 12) - 1)
        for _, row in ipairs(W.segMenu.rows) do
            KE:ApplyFontToText(row.text, face, rowSize, outline)
        end
    end

    -- The hover quick-peek tip (Detail.lua) is a module-level singleton shared by
    -- every window and lives in Detail.lua's file scope, so it can't be reached
    -- through W here. Route the same font/texture reapply through a DM method;
    -- it is a no-op until the tip is first built and is window-agnostic.
    if self.ReapplyHoverTipVisuals then
        self:ReapplyHoverTipVisuals()
    end

    -- Header icons (segment / reset / settings) follow ShowHeaderIcons /
    -- HeaderIconsMouseover. Re-applied here so a live GUI toggle takes effect
    -- without a /reload (CreateWindow does the first apply).
    self:ApplyHeaderIcons(W)
end

---------------------------------------------------------------------------------
-- Header-icon visibility (Phase 4 / Task 7)
--
-- ShowHeaderIcons=false hides all three header buttons outright. When shown,
-- HeaderIconsMouseover=true keeps them at alpha 0 until the window frame is
-- hovered (revealed on OnEnter, hidden again on OnLeave); false leaves them
-- fully visible. Built once in CreateWindow, so this only flips alpha/Show and
-- (re)wires the frame's hover scripts -- safe to call every ApplySettings.
--
-- ALL windows follow the single global HeaderIconsMouseover toggle. (The earlier
-- per-window rule that force-revealed-on-hover every non-#1 window was reverted: the
-- "Only on mouseover" toggle now covers that intent for the whole dock, so a stacked
-- secondary window shows its icons at rest exactly like #1 when the toggle is off.)
---------------------------------------------------------------------------------
-- True when any body-covering overlay (view-selector grid / detail breakdown /
-- segment-menu popup) is open for W. The header icons are children of W.frame, so
-- when one of these mouse-enabled overlays steals W.frame's mouse focus the normal
-- OnLeave path collapses them to alpha 0 and (since the cursor never re-enters
-- W.frame) leaves the controls unreachable -- this predicate keeps them visible while
-- an overlay is up. Single source of truth for the flag set (extend here if a 4th
-- body overlay is ever added).
local function _AnyOverlayOpen(W)
    return W._selectorOpen or W._detailOpen or W._segMenuOpen
end

function DM:ApplyHeaderIcons(W)
    if not W or not W.headerBtns then return end
    local db = self.db
    local show = not db or db.ShowHeaderIcons ~= false
    local mouseover = db and db.HeaderIconsMouseover

    if not show then
        -- Hidden entirely; drop any hover scripts so a stale mouseover handler
        -- can't re-reveal them after the toggle is turned off.
        for _, b in pairs(W.headerBtns) do
            b:Hide()
        end
        if W._headerIconHover then
            self:_UnwireHeaderHover(W)
        end
        return
    end

    -- Shown. Make sure each button frame is visible; the mouseover branch uses
    -- alpha (not Show/Hide) so the frames keep receiving the window's OnEnter.
    for _, b in pairs(W.headerBtns) do
        b:Show()
    end

    if mouseover then
        for _, b in pairs(W.headerBtns) do
            b:SetAlpha(0)
        end
        if not W._headerIconHover and W.headerBar then
            -- Drive the reveal off the dedicated header-bar region (the whole strip,
            -- title -> icons) rather than the window frame, so hovering ANYWHERE on the
            -- header reveals/holds the icons. RevealHeaderIcons shows them; HeaderIconLeave
            -- hides them only on a genuine exit from the strip (it re-checks
            -- headerBar:IsMouseOver, which is geometric over the icons too -- no flicker)
            -- and keeps them up while an overlay is open. The icons' own OnEnter/OnLeave
            -- call the same pair, so entering/leaving directly on an icon is covered too.
            W.headerBar:EnableMouse(true)
            W.headerBar:SetScript("OnEnter", function() DM:RevealHeaderIcons(W) end)
            W.headerBar:SetScript("OnLeave", function() DM:HeaderIconLeave(W) end)
            W._headerIconHover = true
        end
    else
        for _, b in pairs(W.headerBtns) do
            b:SetAlpha(1)
        end
        if W._headerIconHover then
            self:_UnwireHeaderHover(W)
        end
    end
end

-- Hover helper for the mouseover-reveal mode; pulls the icon set to alpha a.
function DM:SetHeaderIconAlpha(W, a)
    if not W or not W.headerBtns then return end
    for _, b in pairs(W.headerBtns) do
        b:SetAlpha(a)
    end
end

-- Force the header icons visible while any overlay is open, restore the at-rest alpha
-- (0) once they all close. Called from every overlay open/close (Selector / Detail /
-- SegmentMenu) so the icons snap to the right state immediately rather than waiting for
-- a W.frame:OnEnter that never comes while a child overlay owns the mouse. No-op unless
-- mouseover-reveal is active for this window (_headerIconHover is false in the
-- always-visible and hide-entirely modes, where the alpha is owned elsewhere).
function DM:SyncHeaderIconsToOverlayState(W)
    if not W or not W.headerBtns or not W._headerIconHover then return end
    self:SetHeaderIconAlpha(W, _AnyOverlayOpen(W) and 1 or 0)
end

-- Reveal the header icons (mouseover-reveal mode only -- no-op otherwise). Called from
-- W.headerBar:OnEnter (the whole header strip is the hover zone) and from each icon's
-- own OnEnter. The latter covers entering the strip directly onto an icon (icons sit at
-- frame level +5, above the headerBar region, so headerBar:OnEnter wouldn't fire there).
-- Paired with HeaderIconLeave, which owns the hide side.
function DM:RevealHeaderIcons(W)
    if not W or not W._headerIconHover then return end
    self:SetHeaderIconAlpha(W, 1)
end

-- The OnLeave counterpart: hide only on a genuine exit. IsMouseOver(W.frame) is
-- geometric -- true while the cursor is anywhere over the window (header band, an icon,
-- the body) -- so icon->icon and icon->header keep the icons up; only leaving the window
-- (or, while an overlay holds them open, never) hides them. W.frame:OnLeave doesn't
-- re-fire after a child stole focus, so this icon-level handler is what catches the
-- icon->outside case. No-op outside mouseover-reveal mode.
function DM:HeaderIconLeave(W)
    if not W or not W._headerIconHover then return end
    if _AnyOverlayOpen(W) then return end
    -- headerBar:IsMouseOver() is geometric and spans the whole header strip (title ->
    -- icons), so it's true while the cursor is on any icon or any bare header area --
    -- only a true exit from the strip hides the icons.
    if W.headerBar and W.headerBar:IsMouseOver() then return end
    self:SetHeaderIconAlpha(W, 0)
end

-- Tear down the header-bar hover wiring and release its mouse capture (so it stops
-- intercepting clicks once mouseover-reveal is off / the icons are hidden entirely).
-- Mirrors the old W.frame teardown the reveal used before it moved to W.headerBar.
function DM:_UnwireHeaderHover(W)
    if W.headerBar then
        W.headerBar:SetScript("OnEnter", nil)
        W.headerBar:SetScript("OnLeave", nil)
        W.headerBar:EnableMouse(false)
    end
    W._headerIconHover = false
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
-- Per-attribute dirty caches: only touch a widget when its value actually changed.
---------------------------------------------------------------------------------

-- Repaints one window. Resolves the live per-context config, sets the header to
-- a readable "<Session> <Type>" label, pulls the cached session (memoized per
-- Tick by Core), and renders up to VisibleBars (hard-clamped to the pool size)
-- bars onto the scrollable content child. The body ScrollFrame clips to the
-- viewport, so a short pane shows the rows that fit and the mouse wheel reaches
-- any overflow; bars beyond the source count are hidden.
function DM:RenderWindow(W)
    local cfg = self:ResolveWindowConfig(W.idx)
    if not cfg or not cfg.Enabled then
        W.frame:Hide()
        return
    end
    W.frame:Show()

    -- Effective meter type: the configured per-context type, or a live in-world view
    -- override (right-click selector, Selector.lua) when one is active for this
    -- segment. Resolved via EffectiveMeterType so the override never mutates the
    -- persisted cfg table (cfg is a live db reference SelectSegment writes to).
    local meterType = self:EffectiveMeterType(W.idx, cfg)

    -- Deaths renders differently: the value shows the death time (M:SS) and the
    -- bar carries no damage-proportional fill. Overall deaths show no time.
    -- Both are plain enum comparisons (cfg.* are config values, never secret),
    -- stashed on W for RenderBar to read without re-resolving the config per bar.
    local isDeaths = (meterType == Enum.DamageMeterType.Deaths)
    W._isDeaths = isDeaths
    W._isOverall = (cfg.SessionType == Enum.DamageMeterSessionType.Overall)
    -- Count-based types (Interrupts / Dispels) have no meaningful per-second:
    -- RenderBar reads this to drop the rate half of the value string, so those
    -- windows show just the count ("3", not "3 | 0"). Plain enum lookup into the
    -- Core.lua whitelist (DM.RATE_METER_TYPES) -- never secret.
    W._isRateType = (self.RATE_METER_TYPES and self.RATE_METER_TYPES[meterType]) == true
    -- Enemy Damage Taken: the sources are enemy mobs (no class), so RenderBar tints their
    -- bars red instead of the classless grey fallback -- it reads as the
    -- "enemy" view at a glance. Plain enum compare; stashed for the per-bar color block.
    W._isEnemyTaken = (meterType == Enum.DamageMeterType.EnemyDamageTaken)

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
    if meterType ~= W._headerType or cfg.SessionType ~= W._headerSession then
        W._headerType = meterType
        W._headerSession = cfg.SessionType
        W.header:SetText(self:FormatWindowLabel(meterType, cfg.SessionType))
        -- Meter-type glyph leads the title. Show + anchor the title to its right when the
        -- type maps to an icon (every selectable type does); otherwise hide it and pull the
        -- title flush-left so no gap is left. Size is owned by LayoutWindow (header font).
        local iconPath = self.METER_TYPE_ICONS and self.METER_TYPE_ICONS[meterType]
        -- Honor the GUI toggle: ShowTypeIcon=false suppresses the glyph and the title
        -- falls flush-left (the no-icon branch below). Default-on when the key is unset.
        if self.db and self.db.ShowTypeIcon == false then iconPath = nil end
        if W.headerIcon then
            W.header:ClearAllPoints()
            if iconPath then
                W.headerIcon:SetTexture(iconPath)
                W.headerIcon:Show()
                -- LEFT->RIGHT so the title centers vertically on the (larger) glyph.
                W.header:SetPoint("LEFT", W.headerIcon, "RIGHT", 3, 0)
            else
                W.headerIcon:Hide()
                W.header:SetPoint("LEFT", W.headerBar, "LEFT", 4, 0)
            end
        end
    end

    -- Phase 4 segment/history: W._curSessionID pins a specific stored session
    -- (set by the ⌚ menu, ToggleSegmentMenu). nil = live cfg.SessionType.
    -- ResolveRenderSession wraps CachedSession (per-Tick memo) and adds the
    -- "Current = last fight" fallback: out of combat, an unpinned Current window
    -- whose live session emptied (post-encounter finalize) shows the newest
    -- stored session instead of blanking out.
    local session = self:ResolveRenderSession(W, cfg, meterType)
    local sources = session and session.combatSources
    if not sources then
        -- No session/data this segment: hide every pooled row so stale bars from
        -- a prior segment don't linger. Gate on IsShown so already-hidden rows
        -- skip the redundant widget call.
        for i = 1, self.BAR_POOL_SIZE do
            local row = W.bars[i].row
            if row:IsShown() then row:Hide() end
        end
        return
    end

    -- Deaths: the API returns death sources most-recent-first and may include
    -- feign deaths (deathRecapID <= 0 = no real recap). Reverse to chronological
    -- and drop feigns into a reused per-window scratch table (no per-tick garbage).
    -- deathRecapID is NeverSecret; still issecretvalue-guarded defensively.
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

    -- Render the FULL source list, clamped only by the pool size (40). VisibleBars
    -- sizes the window (LayoutWindow); rows beyond the viewport land in the scroll
    -- overflow so a raid's whole roster is reachable by wheel -- previously the count
    -- was also clamped to VisibleBars, which left a standalone window with zero
    -- scroll range and the rest of the raid unreachable. #sources is a plain length
    -- (combatSources is a normal array; only the amount FIELDS are secret).
    local count = math_min(#sources, self.BAR_POOL_SIZE)

    -- Scroll model. All `count` rows are rendered onto the content child at their
    -- fixed slots; the body ScrollFrame clips to the viewport and the wheel scrolls
    -- through them, so a short pane (e.g. a 35%-height stacked window) shows the rows
    -- that fit and the user wheels to the rest -- no bar is unreachable. _scrollMax
    -- (rendered height minus viewport) drives the wheel clamp wired in CreateWindow;
    -- re-clamp the live scroll here so shrinking the bar count snaps a now-out-of-range
    -- offset back into view. ScrollFrame clipping cuts a partial bottom row cleanly at
    -- the body edge (no bleed into the next stacked window).
    local stride = W._snapStride or 1
    if stride <= 0 then stride = 1 end
    local viewH = (W.body and W.body:GetHeight()) or 0
    W._scrollMax = math_max(0, count * stride - viewH)
    if W.body then
        local cur = W.body:GetVerticalScroll() or 0
        if cur > W._scrollMax then W.body:SetVerticalScroll(W._scrollMax) end
    end

    -- Grow the scroll child to span every rendered row: the native ScrollFrame
    -- clamps SetVerticalScroll to (content - viewport), so leaving it at the
    -- LayoutWindow base height (VisibleBars rows) would pin the scroll range at 0
    -- and make the overflow unreachable. Never shrink below the base height (a
    -- short list keeps the body's full hit area for the right-click catcher).
    -- Dirty-gated; LayoutWindow nils the cache when it re-sets the base height.
    local contentH = count * stride
    if contentH < (W._contentH or 0) then contentH = W._contentH or 0 end
    if W._renderContentH ~= contentH then
        W._renderContentH = contentH
        W.content:SetHeight(contentH)
    end

    -- Viewport culling. Only rows whose slot intersects the visible scroll window are
    -- RENDERED (RenderBar = SetValue interpolation re-arm + secret-aware SetText); rows
    -- scrolled out of view are just hidden, skipping their per-tick render work. This is
    -- the steady-state win in a dock pane SHORTER than the bar list (a raid with many
    -- sources, stacked into a short pane). When every row fits -- a standalone window or a
    -- tall pane self-sizes so count*stride <= viewH -- the range is the full 1..count, so
    -- this is identical to rendering all (no behavior change for the common case). A 1-row
    -- margin each side keeps a partially scrolled row painted. The mouse-wheel handler
    -- (CreateWindow) re-renders this window on scroll so a row revealed by scrolling is
    -- filled before it shows. stride/viewH/scroll/count are all plain numbers -- never a
    -- secret (only the amount FIELDS are secret, and those go through RenderBar's setters).
    local scroll = 0
    local firstVis, lastVis = 1, count
    if viewH > 0 and count * stride > viewH + 0.5 then
        scroll = (W.body and W.body:GetVerticalScroll()) or 0
        firstVis = math_max(1, math_floor(scroll / stride))
        lastVis = math_min(count, math_ceil((scroll + viewH) / stride) + 1)
    end

    -- Always-show-self: when enabled and the player is NOT within the rows the
    -- viewport currently shows, pin their source into the last fully-visible slot
    -- at their REAL rank -- so self stays on screen at any scroll offset (and in a
    -- raid whose roster overflows the viewport). isLocalPlayer is NeverSecret; a
    -- source's index in the pre-sorted combatSources IS its rank (a plain integer).
    -- No arithmetic/compare on any secret amount anywhere -- the only reads are
    -- isLocalPlayer (boolean, NeverSecret) and plain layout numbers.
    -- Skip Deaths: that view is a chronological event LOG, not a ranked list, so
    -- there is no "self rank" to keep on screen -- pinning the player's death into
    -- a fixed slot just displaces a real death and breaks the time order.
    local pinSource, pinRank, pinSlot
    if self.db and self.db.AlwaysShowSelf and count >= 1 and not isDeaths then
        local inView = false
        for i = firstVis, lastVis do
            local s = sources[i]
            if s and s.isLocalPlayer then inView = true; break end
        end
        if not inView then
            for i = 1, #sources do
                local s = sources[i]
                if s and s.isLocalPlayer then
                    pinSource = s
                    pinRank = i
                    break
                end
            end
            if pinSource then
                -- Last slot whose row bottom still fits inside the viewport (slot i
                -- spans [(i-1)*stride, i*stride], so bottom <= scroll + viewH).
                pinSlot = math_min(count, math_max(firstVis, math_floor((scroll + viewH) / stride)))
            end
        end
    end

    -- maxAmount may be secret in combat; SetMinMaxValues accepts it, and the
    -- per-bar `or 1` fallback in RenderBar hardens against a malformed session
    -- that omits it. Read once here and pass down. Rows in [firstVis, lastVis] are
    -- filled + shown; everything else (above the fold, below count, or past count) is
    -- hidden (no stale bar lingers).
    local maxAmount = session.maxAmount
    for i = 1, self.BAR_POOL_SIZE do
        local bar = W.bars[i]
        local row = bar.row
        if i >= firstVis and i <= lastVis then
            -- The pin slot (last fully-visible row) shows the pinned player at their
            -- real rank when AlwaysShowSelf pinned one; otherwise the slot's own
            -- source. RenderBar's `rank` arg is the displayed rank; the wheel handler
            -- re-renders on scroll, so the pin tracks the moving viewport.
            local src, rank = sources[i], i
            if pinSource and i == pinSlot then
                src, rank = pinSource, pinRank
            end
            self:RenderBar(W, bar, rank, src, maxAmount)
            -- Show only if not already shown.
            if not row:IsShown() then row:Show() end
        else
            -- Hide only if currently shown.
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
        -- M:SS time. A 0-width fill would hide the color
        -- entirely -- the bar would be invisible. No interpolation arg: deaths
        -- bars are static, so the fill snaps full immediately.
        row.fill:SetMinMaxValues(0, 1)
        row.fill:SetValue(1)
    else
        row.fill:SetMinMaxValues(0, maxAmount or 1)
        row.fill:SetValue(src.totalAmount or 0, Enum.StatusBarInterpolation.ExponentialEaseOut)
    end

    -- Fill color. BarColorMode: Class (per-source class color), Custom (db.BarColor),
    -- Theme (the theme accent color). Dirty-keyed so a steady config does NO per-tick
    -- SetStatusBarColor: for Custom/Theme the color is class-independent, so the key is a
    -- mode sentinel ("\1"/"\2", which can't collide with a class filename); for Class it's
    -- the (NEVER-secret) class filename. The Custom color, Theme accent, and BarColorAlpha
    -- all change only via the GUI, where ReapplyBarVisuals nils _cachedColorClass so the next
    -- tick repaints. Falls back to neutral grey for an unknown/absent class. classFilename
    -- is never secret -> taint-safe key + lookup. NOTE: the theme accent MUST be fetched via
    -- KE:GetAccentColor("theme") -- the no-arg call defaults to "custom" mode and returns
    -- white (Core/Colors.lua), which is the bug that made Theme mode paint white bars.
    local classFile = src.classFilename
    local colorMode = db.BarColorMode or "Class"
    -- Resolved class color: nil in Custom/Theme modes, or for a class-less/unknown source.
    -- Enemy mobs report classFilename == "" (NeverSecret, never nil), so test the actual
    -- RAID_CLASS_COLORS lookup -- a bare `not classFile` is wrong (an empty string is truthy).
    local classColor = (colorMode ~= "Custom" and colorMode ~= "Theme") and RAID_CLASS_COLORS[classFile] or nil
    -- Enemy Damage Taken view tints class-less bars red -- Class color mode only;
    -- Custom/Theme keep the user's chosen color. The "\3" sentinel folds this into the dirty
    -- key so a bar reused across a view switch (or once a source resolves a class) repaints.
    local enemyTint = W._isEnemyTaken and not classColor and colorMode ~= "Custom" and colorMode ~= "Theme"
    local colorKey = (colorMode == "Custom" and "\1") or (colorMode == "Theme" and "\2")
        or (enemyTint and "\3") or classFile or "?"
    if bar._cachedColorClass ~= colorKey then
        bar._cachedColorClass = colorKey
        local r, g, b
        if colorMode == "Custom" then
            local bc = db.BarColor
            r, g, b = (bc and bc[1]) or 0.6, (bc and bc[2]) or 0.6, (bc and bc[3]) or 0.6
        elseif colorMode == "Theme" then
            r, g, b = KE:GetAccentColor("theme")
        elseif enemyTint then
            -- Class-less source in the Enemy Damage Taken view: red (0xDD/0x31/0x31).
            r, g, b = 0xDD / 255, 0x31 / 255, 0x31 / 255
        else
            r, g, b = (classColor and classColor.r) or 0.6, (classColor and classColor.g) or 0.6, (classColor and classColor.b) or 0.6
        end
        row.fill:SetStatusBarColor(r, g, b, db.BarColorAlpha or 1)
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
        local nc = nameColorOn and classFile and RAID_CLASS_COLORS[classFile]
        if nc then
            row.name:SetTextColor(nc.r, nc.g, nc.b)
        else
            -- Not class-tinted (toggle off, or an unknown/enemy class with no entry):
            -- use the configured bar text color (db.BarTextColor; white default). Changing
            -- BarTextColor in the GUI nils this cache via ReapplyBarVisuals so it repaints.
            local t = db.BarTextColor
            row.name:SetTextColor((t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1)
        end
    end

    -- Spec icon, resolved in tiers with a class-icon FALLBACK:
    --   1. src.specIconID -- the API's own spec icon (NEVER secret). The client leaves
    --      it nil (the doc claims non-nilable, but it lies) for any player whose spec it
    --      hasn't resolved -- usually EVERYONE in a pug / cross-realm raid.
    --   2. DM.specIconByGUID[sourceGUID] -- a spec icon shared over addon comms by
    --      LibSpecialization (Core.lua's Spec icon resolution section). A player's
    --      sourceGUID is plain at runtime; the read is issecretvalue-guarded so a creature
    --      row (secret GUID in instances) simply skips to the class fallback.
    --   3. the high-res square "classicon-<class>" atlas (KE's standard class-icon source).
    -- A resolved spec (tier 1 or 2) renders the art cropped via ApplyIconZoom; the class
    -- atlas fills the frame edge-to-edge so the shared 1px iconFrame border reads crisp. A
    -- class-less source (enemy mob reports classFilename "") shows NO icon and the layout
    -- drops the gutter -- this generalizes the old _isEnemyTaken special-case (enemy mobs are
    -- exactly the classFilename-empty sources). classFilename/specIconID are NeverSecret, so
    -- no guard there (matching the bar-color block above). Dirty-cached on a signature so a
    -- stable icon does NO per-tick texture call; bar._iconShown gates Show/Hide.
    local showIcon = db.ShowIcon
    local iconID = src.specIconID
    -- classFile (src.classFilename) is already resolved above in the bar-color block.
    local validSpec = type(iconID) == "number" and iconID ~= 0
    -- Tier 2: when the API didn't resolve the spec, try the LibSpec GUID cache before the
    -- class fallback. Only unresolved bars pay this lookup; a tier-1 spec skips it. When the
    -- comms land mid-fight the signature below flips class-token -> spec fileID and repaints.
    if not validSpec then
        local g = src.sourceGUID
        if g and not issecretvalue(g) then
            local libIcon = self.specIconByGUID[g]
            if libIcon then
                iconID = libIcon
                validSpec = true
            end
        end
    end
    local classOK = classFile and classFile ~= ""
    local hasIcon = showIcon and (validSpec or classOK)
    if hasIcon then
        -- Signature: the spec fileID (a number) when valid, else the class token (a string).
        -- A number and a string never compare equal, so the two forms can't collide in the
        -- cache; the signature repaints when a spec resolves (API fills specIconID, or the
        -- LibSpec comms land and tier 2 upgrades class->spec) or a slot is reused by a
        -- different class. Keying spec on the fileID keeps two same-class different-spec sources
        -- correct. (validSpec guarantees iconID is a truthy number, so the and/or is safe; the
        -- class token avoids a per-tick string alloc on the fallback path.)
        local sig = validSpec and iconID or classFile
        if bar._cachedIconID ~= sig then
            bar._cachedIconID = sig
            if validSpec then
                row.icon:SetTexture(iconID)
                KE:ApplyIconZoom(row.icon)
            else
                -- Class fallback: the "classicon-<class>" atlas. SetAtlas re-sets the texcoords
                -- to the atlas region, cleanly overriding the spec path's ApplyIconZoom crop, and
                -- the atlas is a full square (no transparent corners) so it fills the frame and the
                -- iconFrame border stays crisp. classFile is a non-empty NeverSecret token here.
                row.icon:SetAtlas("classicon-" .. classFile:lower())
            end
        end
        if bar._iconShown ~= true then
            bar._iconShown = true
            row.iconFrame:Show()
        end
    elseif bar._iconShown ~= false then
        bar._iconShown = false
        bar._cachedIconID = nil
        row.iconFrame:Hide()
    end

    -- Layout (rank-gutter / icon / name LEFT anchors), dirty-gated on the
    -- (hasIcon, ShowRank) combination so a stable config does NO per-tick re-anchor.
    -- hasIcon (not the raw ShowIcon) is the key so an icon-less enemy row drops the icon
    -- gutter and the name goes flush left. When ShowRank is on, the rank occupies a fixed
    -- left gutter and the icon/name start to its right -- fixing the rank-label-over-icon
    -- overlap; when off, the icon (or name) sits flush at the left edge as before.
    local showRank = db.ShowRank
    local layoutKey = (hasIcon and 1 or 0) + (showRank and 2 or 0)
    if bar._layoutKey ~= layoutKey then
        bar._layoutKey = layoutKey

        -- Rank gutter: left-justified within a fixed slot (width scales with the
        -- font) so the icon/name to its right start at a deterministic x.
        local gutter = KE:PixelSnap((db.FontSize or 12) + 8)
        row.rank:ClearAllPoints()
        -- Anchor to the ROW (not row.fill) so vertical centering survives BarThinLine mode
        -- (thin fill = bottom strip); identical to row.fill in normal mode (fill == row).
        row.rank:SetPoint("LEFT", row, "LEFT", 3, 0)
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
        if hasIcon then
            row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
        elseif showRank then
            row.name:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
        else
            -- Flush at the row's left edge (anchored to the ROW, not row.fill, so it stays
            -- centered in BarThinLine mode; equal to row.fill in normal mode).
            row.name:SetPoint("LEFT", row, "LEFT", 3, 0)
        end
        row.name:SetPoint("RIGHT", row.value, "LEFT", -3, 0)
    end

    -- Name (secret-aware). In combat src.name may be secret: SetText accepts it,
    -- but == / ~= on a secret string throws, so set it unconditionally and null
    -- the cache. Out of combat it's a plain string and dirty-checked. Visibility
    -- tracks ShowName every tick so the GUI toggle takes effect on the next paint.
    local nm = src.name
    if issecretvalue(nm) then
        -- Secret name (identity-restricted unit -- group members inside a raid or an active
        -- keystone; source.name is ConditionalSecret in DamageMeterDocumentation). Ambiguate
        -- is SecretArguments=AllowedWhenTainted (PlayerScriptDocumentation) -- it accepts the
        -- secret name WITHOUT throwing and returns the realm-stripped form (itself secret;
        -- SetText accepts that). Ambiguate(name, "short") is the reference strip on both the
        -- secret and plain paths.
        -- (The old strip was UnitName(source.name): UnitName wants a UNIT token, not a name
        -- string, so it returned nil and the "-Realm" suffix leaked through in raids.)
        -- Honor ShowRealm: only strip when off; when on, keep the full secret "Name-Realm".
        -- Cache nulled (can't dirty-check a maybe-secret string), so it re-resolves each tick.
        local shown = nm
        if not db.ShowRealm then
            shown = Ambiguate(nm, "short") or nm
        end
        row.name:SetText(shown)
        bar._cachedName = nil
        bar._rawName = nil
    else
        -- Plain string. Stash the UNSTRIPPED name first: the Detail Targets sub-section
        -- keys its per-player lookup on the raw det.unitName (which carries the
        -- "-Realm" suffix for cross-realm members), so it must match against the raw
        -- name, never the realm-stripped display name.
        bar._rawName = nm
        if nm then
            if db.ShowRealm then
                -- Stabilize the realm suffix. The source name resolves to "Name-Realm"
                -- while the unit is fully known but intermittently drops to bare "Name"
                -- (e.g. across a phase transition), so rendering it verbatim flickers.
                -- sourceGUID is immutable per character and issecretvalue-guarded below
                -- (a secret guid is skipped): memoize the realm-bearing form keyed on it
                -- and never DOWNGRADE -- once a cross-realm member has
                -- shown its realm, keep it on the ticks the API drops it. A same-realm name
                -- has no hyphen so it's never stored and just passes through.
                local guid = bar._sourceGUID
                if guid and not issecretvalue(guid) then
                    if nm:find("-", 1, true) then
                        realmNames[guid] = nm
                    elseif realmNames[guid] then
                        nm = realmNames[guid]
                    end
                end
            else
                -- ShowRealm off (default): drop the "-Realm" suffix for DISPLAY only. A
                -- character name never contains a hyphen -- the only hyphen is the realm
                -- separator -- so matching up to the first hyphen is exact and UTF-8 safe
                -- (no multibyte sequence contains the 0x2D byte). The stripped string is
                -- what gets dirty-cached, so toggling ShowRealm repaints on the next tick.
                nm = nm:match("^[^-]+") or nm
            end
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
    -- null-cache contract as the name. NumberFormat (read once) gates the per-second
    -- half: only the Both / PerSec modes pass the perSec arg, so an Amount-only config
    -- never touches the secret amountPerSecond.
    -- Deaths show the death time (M:SS) instead of amount|perSec, and Overall
    -- deaths show nothing (cumulative time across segments isn't meaningful).
    -- FormatDeathTime / FormatBarValue both return
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
        -- Number Format: "Both" -> amount | dps, "PerSec" -> dps only, else amount only.
        -- Only read the (secret-in-combat) amountPerSecond when the mode actually shows it,
        -- so an Amount-only config never touches it. FormatBarValue is secret-safe.
        -- Count types (W._isRateType false: Interrupts / Dispels) never pass a rate --
        -- the count alone renders, and the "PerSec" mode falls back to it inside
        -- FormatBarValue (the value is never blank).
        local mode = db.NumberFormat or "Both"
        local needPerSec = (mode == "Both" or mode == "PerSec") and W._isRateType
        v, vIsSecret = self.FormatBarValue(
            src.totalAmount,
            needPerSec and src.amountPerSecond or nil,
            mode
        )
    end
    if vIsSecret then
        row.value:SetText(v)
        bar._cachedVal = nil
    elseif v ~= bar._cachedVal then
        bar._cachedVal = v
        row.value:SetText(v)
    end

    -- Value text color (db.BarTextColor; the value column is never class-tinted). Set HERE
    -- per tick -- not only in ReapplyBarVisuals -- so a saved non-white color is correct on
    -- the FIRST paint (ReapplyBarVisuals isn't called at enable; CreateAllWindows -> Tick is).
    -- Dirty-cached on the table reference: the GUI replaces db.BarTextColor with a fresh
    -- table on edit, and ReapplyBarVisuals nils this cache after re-applying the font (which
    -- resets the FontString color), so both a color change and a font change repaint next tick.
    local tcol = db.BarTextColor
    if bar._cachedValColorTbl ~= tcol then
        bar._cachedValColorTbl = tcol
        row.value:SetTextColor((tcol and tcol[1]) or 1, (tcol and tcol[2]) or 1, (tcol and tcol[3]) or 1)
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
