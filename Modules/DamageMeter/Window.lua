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
    --   _cachedIconClass  -- class driving the spec-icon SetTexture (NEVER secret)
    --   _cachedName       -- last plain (non-secret) name string set; nil while secret
    --   _cachedVal        -- last plain (non-secret) value string set; nil while secret
    --   _cachedSlot       -- last displayed rank whose "N." label was set (may be
    --                        a pinned player's real rank, not the pool slot index)
    --   _iconShown        -- cached icon visibility (starts false: icon is hidden
    --                        below) so a stable ShowIcon does no per-tick Show/Hide
    bar._cachedColorClass = nil
    bar._cachedIconClass = nil
    bar._cachedName = nil
    bar._cachedVal = nil
    bar._cachedSlot = nil
    bar._iconShown = false

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

    -- Fixed header band (font-size driven, snapped). The header FontString is
    -- anchored TOPLEFT inside this band; the body starts immediately below it.
    local headerH = KE:PixelSnap(fontSize + 6)

    -- Body height fits VisibleBars rows (clamped to the pool). stride is the
    -- snapped per-row advance from CreateWindow; guard against a 0 stride.
    local visible = math_min((db and db.VisibleBars) or 10, BAR_POOL_SIZE)
    local stride = W._snapStride or 1
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
        local typeName = self.METER_TYPE_NAMES[cfg.MeterType] or "Damage Done"
        local sessName = self.SESSION_TYPE_NAMES[cfg.SessionType]
        local label
        if sessName and cfg.SessionType ~= Enum.DamageMeterSessionType.Current then
            label = sessName .. " " .. typeName
        else
            label = typeName
        end
        W.header:SetText(label)
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

    -- Always-show-self: when enabled and the player is NOT within the visible top
    -- `count`, pin the player's source into the last visible slot. isLocalPlayer
    -- is NeverSecret; a source's index in the pre-sorted combatSources IS its rank
    -- (a plain integer). No arithmetic/compare on any secret amount anywhere — the
    -- only reads are isLocalPlayer (boolean, NeverSecret) and the loop index.
    local pinSource, pinRank
    if self.db and self.db.AlwaysShowSelf and count >= 1 then
        local inVisible = false
        for i = 1, count do
            local s = sources[i]
            if s and s.isLocalPlayer then inVisible = true; break end
        end
        if not inVisible then
            for i = count + 1, #sources do
                local s = sources[i]
                if s and s.isLocalPlayer then
                    pinSource = s
                    pinRank = i
                    break
                end
            end
        end
    end

    -- Visible scroll range (mirrors EllesmereUI ~2767-2770). stride is the
    -- snapped per-row advance computed in CreateWindow. Scrolling isn't wired in
    -- Phase 1, so scrollOff is normally 0 and this resolves to 1..count, but the
    -- viewport math is in place for when the scrollbar lands.
    local stride = W._snapStride or 1
    if stride <= 0 then stride = 1 end
    local scrollOff = (W.body and W.body:GetVerticalScroll()) or 0
    local viewH = (W.body and W.body:GetHeight()) or 0
    local visFirst, visLast
    if viewH > 0 then
        visFirst = math.floor(scrollOff / stride) + 1
        visLast = math_min(count, math.ceil((scrollOff + viewH) / stride))
    else
        -- Viewport not sized yet (first paint before layout): render the whole
        -- visible set so bars aren't left blank.
        visFirst, visLast = 1, count
    end

    -- maxAmount may be secret in combat; SetMinMaxValues accepts it, and the
    -- per-bar `or 1` fallback in RenderBar hardens against a malformed session
    -- that omits it. Read once here and pass down.
    local maxAmount = session.maxAmount
    for i = 1, self.BAR_POOL_SIZE do
        local bar = W.bars[i]
        local row = bar.row
        if i <= count then
            if i >= visFirst and i <= visLast then
                -- The last visible slot shows the pinned player (with the player's
                -- real rank R) when AlwaysShowSelf pinned one; otherwise the slot's
                -- own source. RenderBar's `i` arg is the displayed rank.
                local src, rank = sources[i], i
                if pinSource and i == count then
                    src, rank = pinSource, pinRank
                end
                self:RenderBar(W, bar, rank, src, maxAmount)
            end
            -- Show only if not already shown (mirrors EllesmereUI ~2776); skips
            -- the redundant widget call on rows that are already visible.
            if not row:IsShown() then row:Show() end
        else
            -- Hide only if currently shown (mirrors EllesmereUI ~2887); with
            -- VisibleBars defaulting to 10 this avoids ~30 redundant Hide() calls
            -- per window per tick once the pool tail has settled hidden.
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
        -- Deaths: no damage-proportional fill. SetValue(0) leaves the bar empty
        -- (no colored bar) while the row text -- children of the fill -- stays
        -- visible. (EllesmereUI fills it via SetValue(1); we keep it empty.)
        row.fill:SetMinMaxValues(0, 1)
        row.fill:SetValue(0)
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

    -- Name color: read ClassColorName EVERY tick and set the tint outside the
    -- fill-color dirty cache (mirrors EllesmereUI ~2838-2847, which sets the
    -- label color unconditionally when class-color is on and resets it when off).
    -- Gating this on the class dirty cache would leave the name tinted after the
    -- user toggles ClassColorName off (until the class happened to change), so it
    -- must be independent of _cachedColorClass.
    if db.ClassColorName then
        local nc = classFile and RAID_CLASS_COLORS[classFile]
        if nc then
            row.name:SetTextColor(nc.r, nc.g, nc.b)
        else
            row.name:SetTextColor(1, 1, 1)
        end
    else
        row.name:SetTextColor(1, 1, 1)
    end

    -- Spec icon (dirty-cached on classFilename; specIconID is NEVER secret).
    -- Re-applies the standard KE icon zoom on change. Visibility is cached in
    -- bar._iconShown so a stable ShowIcon setting does NO per-tick Show/Hide
    -- widget call -- the toggle still takes effect on the next paint because the
    -- cached flag flips when the setting changes.
    local showIcon = db.ShowIcon
    if showIcon then
        if bar._cachedIconClass ~= classFile then
            bar._cachedIconClass = classFile
            row.icon:SetTexture(src.specIconID)
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

    -- Name's LEFT anchor depends on icon visibility, cached in bar._nameIconAnchored
    -- so a stable ShowIcon does NO per-tick re-anchor: after the icon frame when
    -- shown, at the fill's left edge when hidden (so disabling the icon doesn't
    -- leave a blank icon-width column on the left of every name).
    if bar._nameIconAnchored ~= showIcon then
        bar._nameIconAnchored = showIcon
        row.name:ClearAllPoints()
        if showIcon then
            row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 3, 0)
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
    if db.ShowName then
        row.name:Show()
    else
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
        row.rank:Show()
    else
        row.rank:Hide()
    end

    -- Percent: secret in combat; left hidden for Phase 1 (ShowPercent defaults
    -- false). An out-of-combat percent is a later phase -- do NOT compute one
    -- here (would require arithmetic on amounts that are secret in combat).
end
