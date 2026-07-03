-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/SegmentMenu.lua                             ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: Custom hover dropdown for the segment/history  ║
-- ║          picker (⌚ header icon). Replaces the Blizzard  ║
-- ║          MenuUtil context menu so it can (1) open on     ║
-- ║          hover, (2) grow UPWARD from the icon, and (3)   ║
-- ║          carry KE's own high-contrast styling -- none of ║
-- ║          which the context-menu primitive allows.        ║
-- ║          Taint-safe: rows only call SelectSegment->Tick  ║
-- ║          (same as the old menu); session names stay      ║
-- ║         secret-guarded (SafeSessionName/FormatDeathTime).║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local Enum = Enum
local ipairs = ipairs
local pairs = pairs
local select = select
local max = math.max
local floor = math.floor

-- The live Current/Overall pair offered under the session list. Built once at file
-- load (plain enum order, Current first) -- a Core.lua local of the same name owns
-- the data helpers; this is the presentation layer's own copy.
local SEGMENT_SESSION_TYPES = {
    Enum.DamageMeterSessionType.Current,
    Enum.DamageMeterSessionType.Overall,
}

local SEG_W = 198          -- MINIMUM panel width (px); the panel widens to match its
                           -- window (PopulateSegmentMenu) so long names + times fit --
                           -- names still truncate (no wrap) past that
local SEG_PAD = 3          -- inner padding inside the viewport
local SEG_ROW_GAP = 1      -- vertical gap between rows
local SEG_DIV_H = 1        -- divider line thickness
local SEG_MAX_H = 300      -- panel caps here and the session list scrolls when taller

-- Resting paint for a row: accent fill + white text when it's the active pick,
-- transparent + dim text otherwise. The hover highlight (row.hl) is separate and
-- layered above this, so hovering never disturbs the active mark. ar/ag/ab are plain
-- accent components; active is a plain boolean (sessionID / SessionType compares only).
local function PaintSegRowActive(row, active, ar, ag, ab)
    row._active = active
    if active then
        row.bg:SetColorTexture(ar or 0.6, ag or 0.6, ab or 0.6, 0.34)
        row.bg:Show()
        row.text:SetTextColor(1, 1, 1)
    else
        row.bg:Hide()
        row.text:SetTextColor(0.82, 0.82, 0.82)
    end
end

-- One pooled row button: [name (M:SS)] with an active-fill texture, a hover
-- highlight, and a label. W is captured (the panel is per-window) so the click knows
-- its window. Left-click pins the row's session/type and closes; OnLeave schedules the
-- hover-away close (re-checked against IsMouseOver, so moving onto a sibling row or the
-- panel body never closes it). Font set once here; ReapplyBarVisuals refreshes it.
local function MakeSegRow(parent, W, db)
    local row = CreateFrame("Button", nil, parent)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:Hide()
    row.hl = row:CreateTexture(nil, "BORDER")
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(1, 1, 1, 0.16)
    row.hl:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    KE:ApplyFontToText(row.text, db and db.FontFace, max(8, ((db and db.FontSize) or 12) - 1), db and db.FontOutline)

    row:SetScript("OnEnter", function(r)
        r.hl:Show()
        r.text:SetTextColor(1, 1, 1)
    end)
    row:SetScript("OnLeave", function(r)
        r.hl:Hide()
        -- Restore the resting text tint (white when this is the active pick, dim
        -- otherwise) so the active mark survives a hover.
        if r._active then r.text:SetTextColor(1, 1, 1) else r.text:SetTextColor(0.82, 0.82, 0.82) end
        DM:ScheduleSegmentClose(W)
    end)
    row:SetScript("OnClick", function(r)
        DM:SelectSegment(W, r._sid, r._sType)
        DM:CloseSegmentMenu(W)
    end)
    return row
end

-- Lazily build W.segMenu: a dark bordered panel (parented to the window, above the
-- bars) holding a scroll viewport + content child for the rows. Idempotent. The panel
-- and rows enable mouse so the cursor can travel from the ⌚ icon onto the list without
-- the hover-away timer firing (it re-checks IsMouseOver). The wheel scrolls when the
-- session list is taller than SEG_MAX_H.
function DM:EnsureSegmentMenu(W)
    if W.segMenu then return W.segMenu end
    local s = CreateFrame("Frame", nil, W.frame, "BackdropTemplate")
    s:SetFrameLevel(W.frame:GetFrameLevel() + 10)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    s:SetBackdropBorderColor(0, 0, 0, 1)
    s:EnableMouse(true)
    s:SetScript("OnLeave", function() DM:ScheduleSegmentClose(W) end)
    s:Hide()

    -- Viewport anchored at the TOP only; PopulateSegmentMenu sets its SIZE. The
    -- Current/Overall footer owns the panel's bottom band (outside the scroll), so
    -- a bottom anchor would let the list slide under it.
    s.view = CreateFrame("ScrollFrame", nil, s)
    s.view:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    s.content = CreateFrame("Frame", nil, s.view)
    s.content:SetSize(1, 1)
    s.view:SetScrollChild(s.content)
    -- One wheel handler serves the viewport AND the panel itself: the footer band
    -- (Current/Overall) sits OUTSIDE the viewport, and a wheel over a frame that
    -- never registered for it falls THROUGH to whatever is behind the menu -- in a
    -- stacked dock that's the window above, which would scroll its bars. Routing
    -- the panel's wheel into the same list scroll plugs the leak and reads naturally.
    local function onWheel(_, delta)
        local viewH = s.view:GetHeight() or 0
        local contentH = s.content:GetHeight() or 0
        local maxScroll = contentH - viewH
        if maxScroll <= 0 then s.view:SetVerticalScroll(0); return end
        local step = ((DM.db and DM.db.FontSize) or 12) + 10
        local new = (s.view:GetVerticalScroll() or 0) - delta * step
        if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
        s.view:SetVerticalScroll(new)
    end
    s.view:EnableMouseWheel(true)
    s.view:SetScript("OnMouseWheel", onWheel)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", onWheel)

    -- Divider = the footer's top edge. Parented to the PANEL (not the scroll
    -- content) because the Current/Overall rows below it never scroll.
    s.divider = s:CreateTexture(nil, "ARTWORK")
    s.divider:SetColorTexture(1, 1, 1, 0.18)
    s.divider:Hide()

    s.rows = {}
    s.footRows = {}   -- pinned Current/Overall rows (fixed footer, never scrolled)
    W.segMenu = s
    return s
end

-- Rebuild the row list from the current sessions every open (the generator pattern --
-- the list is always fresh). The stored sessions (up to 20, name + M:SS, accent-filled
-- when pinned) fill the SCROLL list; Current / Overall live in a FIXED footer below it,
-- always visible at any scroll offset (they used to scroll away with a long history),
-- separated by the divider. The panel matches its window's width (floored at SEG_W) so
-- long names + durations fit; the list caps at SEG_MAX_H and scrolls, opening
-- pre-scrolled to the NEWEST stored sessions (bottom, nearest the footer).
function DM:PopulateSegmentMenu(W)
    local s = W.segMenu
    if not s then return end
    local db = self.db
    local ar, ag, ab = KE:GetAccentColor()
    -- Panel width tracks the anchor window ("same size as one panel"), floored at
    -- the legacy fixed width so a skinny window can't crush the labels.
    local segW = SEG_W
    local winW = W.frame and W.frame:GetWidth()
    if winW and winW > segW then segW = floor(winW + 0.5) end
    local viewW = segW - 2
    s.content:SetWidth(viewW)
    local rowW = viewW - SEG_PAD * 2
    local rowH = max(16, ((db and db.FontSize) or 12) + 8)
    local rows = s.rows
    local idx = 0
    local y = -SEG_PAD

    local function place(text, active, sid, sType)
        idx = idx + 1
        local row = rows[idx]
        if not row then
            row = MakeSegRow(s.content, W, db)
            rows[idx] = row
        end
        row._sid = sid
        row._sType = sType
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", s.content, "TOPLEFT", SEG_PAD, y)
        row:SetSize(rowW, rowH)
        row.text:SetText(text)
        PaintSegRowActive(row, active, ar, ag, ab)
        row:Show()
        y = y - (rowH + SEG_ROW_GAP)
    end

    -- Stored sessions (newest nearest the icon). sessionID is a plain id (NeverSecret)
    -- so the active == compare is taint-safe; name/duration are secret-guarded.
    local list = self:GetAvailableSessions(20)
    local hadSessions = false
    -- Kill/wipe tint map: tagged on ENCOUNTER_END's authoritative success flag
    -- (Core.lua) -- NOT parsed from the session name, which stays verbatim
    -- (including Blizzard's own markers). Runtime-only, like stored sessions.
    local outcomes = self._sessionOutcomes
    if list and #list > 0 then
        for i = 1, #list do
            local sdata = list[i]
            if sdata then
                local sid = sdata.sessionID
                local label = self:SafeSessionName(sdata.name)
                -- Green kill / red wipe; untagged rows (trash, pre-tag) keep plain
                -- text. The escape-code wrap overrides the row's SetTextColor tints
                -- for the name span, which is fine: active/hover feedback still
                -- comes from the bg fill + highlight texture. Plain concat -- safe
                -- even when the duration half below is a secret string.
                local outcome = outcomes and outcomes[sid]
                if outcome == true then
                    label = "|cff33ff33" .. label .. "|r"
                elseif outcome == false then
                    label = "|cffff3333" .. label .. "|r"
                end
                local dur = select(1, self.FormatDeathTime(sdata.durationSeconds))
                place(label .. "  |cff999999(" .. dur .. ")|r", W._curSessionID == sid, sid, nil)
                hadSessions = true
            end
        end
    end

    -- Hide any leftover pooled rows from a longer previous list.
    for i = idx + 1, #rows do rows[i]:Hide() end

    -- Fixed footer: Current / Overall pinned at the panel bottom (nearest the ⌚
    -- icon the menu grows up from), OUTSIDE the scroll viewport so a long history
    -- can't scroll them away. Active when nothing is pinned AND the type matches
    -- the window's resolved per-context config -- all plain enum compares. Rows
    -- pooled once in s.footRows; live font changes reach them via Window.lua
    -- ReapplyBarVisuals exactly like the scroll rows.
    local cfg = self:ResolveWindowConfig(W.idx)
    for fi, sType in ipairs(SEGMENT_SESSION_TYPES) do
        local row = s.footRows[fi]
        if not row then
            row = MakeSegRow(s, W, db)
            s.footRows[fi] = row
        end
        row._sid = nil
        row._sType = sType
        row:ClearAllPoints()
        -- Stack upward from the bottom border: the LAST entry (Overall) sits lowest.
        row:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 1 + SEG_PAD,
            1 + SEG_PAD + (#SEGMENT_SESSION_TYPES - fi) * (rowH + SEG_ROW_GAP))
        row:SetSize(rowW, rowH)
        row.text:SetText((self.SESSION_TYPE_NAMES and self.SESSION_TYPE_NAMES[sType]) or "Unknown")
        PaintSegRowActive(row, (W._curSessionID == nil and cfg ~= nil and cfg.SessionType == sType), ar, ag, ab)
        row:Show()
    end
    -- Footer band height: inner pad + the footer rows + the divider band above them.
    local footerH = SEG_PAD + #SEGMENT_SESSION_TYPES * (rowH + SEG_ROW_GAP) + SEG_DIV_H + 2

    -- Divider = the footer's top edge; hidden when no scroll list sits above it.
    if hadSessions then
        s.divider:ClearAllPoints()
        s.divider:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 1 + SEG_PAD,
            1 + SEG_PAD + #SEGMENT_SESSION_TYPES * (rowH + SEG_ROW_GAP) + 2)
        s.divider:SetSize(rowW, SEG_DIV_H)
        s.divider:Show()
    else
        s.divider:Hide()
    end

    -- Scroll-list viewport: everything above the footer, capped so the whole panel
    -- stays under SEG_MAX_H. Open pre-scrolled to the BOTTOM of the list -- the
    -- newest stored sessions sit there, adjacent to the footer. A short list has
    -- maxScroll == 0 (the view fits the content exactly) and the floor below keeps
    -- a negative out of SetVerticalScroll -- do NOT rely on native ScrollFrame
    -- clamping (the wheel handler above clamps manually for the same reason).
    local contentH = hadSessions and ((-y) - SEG_ROW_GAP + SEG_PAD) or 0
    s.content:SetHeight(max(contentH, 1))
    local viewH = contentH
    local maxViewH = SEG_MAX_H - footerH - 2
    if viewH > maxViewH then viewH = maxViewH end
    s.view:SetSize(viewW, max(viewH, 1))
    s:SetSize(segW, viewH + footerH + 2)
    local maxScroll = contentH - viewH
    s.view:SetVerticalScroll(maxScroll > 0 and maxScroll or 0)
end

-- Show the picker, anchored to grow UPWARD from the ⌚ icon (BOTTOMRIGHT of the panel
-- pinned to the icon's TOPRIGHT, right-aligned). Safe in combat -- the rows are static
-- text and SelectSegment is taint-safe.
--
-- This lightweight popup floats ABOVE the header band, clear of the view-selector grid
-- (which fills the body BELOW it), so the two COEXIST: hovering the ⌚ while the grid is
-- open just floats this menu above it -- it no longer tears the grid down (a stray hover
-- must not snap the bars back). It still YIELDS to the detail breakdown, though: detail
-- shows per-source data for a SPECIFIC segment, so letting the ⌚ retarget the segment
-- under an open detail panel would leave it showing stale data.
function DM:OpenSegmentMenu(W)
    if not W then return end
    if W._detailOpen then return end
    self:EnsureSegmentMenu(W)
    self:PopulateSegmentMenu(W)
    local s = W.segMenu
    local anchor = (W.headerBtns and W.headerBtns.segment) or W.frame
    s:ClearAllPoints()
    s:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    W._segMenuOpen = true
    s:Show()
    if self.SyncHeaderIconsToOverlayState then self:SyncHeaderIconsToOverlayState(W) end
end

function DM:CloseSegmentMenu(W)
    if not W or not W.segMenu then return end
    W._segMenuOpen = false
    W.segMenu:Hide()
    if self.SyncHeaderIconsToOverlayState then self:SyncHeaderIconsToOverlayState(W) end
end

-- Close any open segment menu across every window. Wired into the same boundary /
-- teardown paths as CloseAllSelectors (segment bump, combat start, reset, EditMode) so
-- a stale picker never floats over a re-laid-out dock. Idempotent + nil-safe.
function DM:CloseAllSegmentMenus()
    if not self.windows_rt then return end
    for _, W in pairs(self.windows_rt) do
        if W._segMenuOpen then self:CloseSegmentMenu(W) end
    end
end

-- Hover-away close with a short grace: the ⌚ icon is tiny, so leaving it (or a row)
-- schedules a close that only fires if, after the grace, the cursor is over NEITHER the
-- panel nor the icon -- letting the mouse travel across the 2px gap onto the list.
function DM:ScheduleSegmentClose(W)
    if not W or not W._segMenuOpen then return end
    C_Timer.After(0.2, function()
        if not W._segMenuOpen or not W.segMenu then return end
        if W.segMenu:IsMouseOver() then return end
        local icon = W.headerBtns and W.headerBtns.segment
        if icon and icon:IsMouseOver() then return end
        DM:CloseSegmentMenu(W)
    end)
end

-- Click toggle (the ⌚ icon's OnClick). Hover uses OpenSegmentMenu directly; click
-- gives a deliberate open/close affordance.
function DM:ToggleSegmentMenu(W)
    if not W then return end
    if W._segMenuOpen then
        self:CloseSegmentMenu(W)
    else
        self:OpenSegmentMenu(W)
    end
end
