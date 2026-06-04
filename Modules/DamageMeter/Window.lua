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

    -- Per-attribute dirty caches. These are the exact fields the render path
    -- (RenderBar) reads/writes; declared here so the factory documents the live
    -- bar state and the fields exist on a fresh row before first paint.
    --   _cachedColorClass -- class driving the fill SetStatusBarColor (NEVER secret)
    --   _cachedIconClass  -- class driving the spec-icon SetTexture (NEVER secret)
    --   _cachedName       -- last plain (non-secret) name string set; nil while secret
    --   _cachedVal        -- last plain (non-secret) value string set; nil while secret
    --   _cachedSlot       -- last rank slot index whose "N." label was set
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
    --
    -- The body anchors to the header's BOTTOMLEFT with a -4 X offset to cancel
    -- the header's +4 left padding (the header is inset 4px from the frame's
    -- TOPLEFT above), so the scroll viewport's left edge lines up with the
    -- frame's left edge. The header's height is font-driven and zero until the
    -- render layer calls SetText, so the body's TOPLEFT briefly collapses at
    -- construction time; the layout pass resolves it once the title is set.
    W.body = CreateFrame("ScrollFrame", nil, W.frame)
    W.body:SetPoint("TOPLEFT", W.header, "BOTTOMLEFT", -4, -2)
    W.body:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)

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
    local barSpacing = (self.db and self.db.BarSpacing) or 0
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

    self.windows_rt = self.windows_rt or {}
    self.windows_rt[winIdx] = W

    return W
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

    -- Clamp the bar count to VisibleBars and the pool size (40). #sources is a
    -- plain length (combatSources is a normal array; only the amount FIELDS are
    -- secret), so math.min on it is safe.
    local count = math_min(#sources, (self.db and self.db.VisibleBars) or 10, self.BAR_POOL_SIZE)

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
                self:RenderBar(W, bar, i, sources[i], maxAmount)
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
-- W is part of the documented signature (callers pass the owning window and a
-- later phase -- detail breakdown / sticky-player row -- reads it); unused here.
function DM:RenderBar(W, bar, i, src, maxAmount) -- luacheck: ignore 212/W
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
    row.fill:SetMinMaxValues(0, maxAmount or 1)
    row.fill:SetValue(src.totalAmount or 0, Enum.StatusBarInterpolation.ExponentialEaseOut)

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
        if not bar._iconShown then
            bar._iconShown = true
            row.icon:Show()
        end
    elseif bar._iconShown ~= false then
        bar._iconShown = false
        row.icon:Hide()
    end

    -- Name (secret-aware). In combat src.name may be secret: SetText accepts it,
    -- but == / ~= on a secret string throws, so set it unconditionally and null
    -- the cache. Out of combat it's a plain string and dirty-checked. Visibility
    -- tracks ShowName every tick so the GUI toggle takes effect on the next paint.
    local nm = src.name
    if issecretvalue(nm) then
        row.name:SetText(nm)
        bar._cachedName = nil
    elseif nm ~= bar._cachedName then
        bar._cachedName = nm
        row.name:SetText(nm)
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
    local showPerSec = db.ShowPerSec
    local v = self.FormatBarValue(
        src.totalAmount,
        showPerSec and src.amountPerSecond or nil,
        showPerSec
    )
    if issecretvalue(v) then
        row.value:SetText(v)
        bar._cachedVal = nil
    elseif v ~= bar._cachedVal then
        bar._cachedVal = v
        row.value:SetText(v)
    end

    -- Rank: "N." label, dirty-cached on the slot (the loop index, which equals
    -- the API rank). Visibility tracks ShowRank every tick.
    if db.ShowRank then
        if bar._cachedSlot ~= i then
            bar._cachedSlot = i
            row.rank:SetText(self.RANK_STRINGS[i])
        end
        row.rank:Show()
    else
        row.rank:Hide()
    end

    -- Percent: secret in combat; left hidden for Phase 1 (ShowPercent defaults
    -- false). An out-of-combat percent is a later phase -- do NOT compute one
    -- here (would require arithmetic on amounts that are secret in combat).
end
