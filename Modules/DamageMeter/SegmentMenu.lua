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

-- The live Current/Overall pair offered under the session list. Built once at file
-- load (plain enum order, Current first) -- a Core.lua local of the same name owns
-- the data helpers; this is the presentation layer's own copy.
local SEGMENT_SESSION_TYPES = {
    Enum.DamageMeterSessionType.Current,
    Enum.DamageMeterSessionType.Overall,
}

local SEG_W = 198          -- panel width (px); names truncate (no wrap) to fit
local SEG_PAD = 3          -- inner padding inside the viewport
local SEG_ROW_GAP = 1      -- vertical gap between rows
local SEG_DIV_H = 1        -- divider line thickness
local SEG_MAX_H = 300      -- panel caps here and scrolls when the list is taller

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

    s.view = CreateFrame("ScrollFrame", nil, s)
    s.view:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    s.view:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    s.content = CreateFrame("Frame", nil, s.view)
    s.content:SetSize(1, 1)
    s.view:SetScrollChild(s.content)
    s.view:EnableMouseWheel(true)
    s.view:SetScript("OnMouseWheel", function(self, delta)
        local viewH = self:GetHeight() or 0
        local contentH = s.content:GetHeight() or 0
        local maxScroll = contentH - viewH
        if maxScroll <= 0 then self:SetVerticalScroll(0); return end
        local step = ((DM.db and DM.db.FontSize) or 12) + 10
        local new = (self:GetVerticalScroll() or 0) - delta * step
        if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)

    s.divider = s.content:CreateTexture(nil, "ARTWORK")
    s.divider:SetColorTexture(1, 1, 1, 0.18)
    s.divider:Hide()

    s.rows = {}
    W.segMenu = s
    return s
end

-- Rebuild the row list from the current sessions every open (the generator pattern --
-- the list is always fresh). Order: up to the last 20 stored sessions (name + M:SS,
-- accent-filled when pinned), a divider, then Current / Overall (filled when live and
-- matching the resolved config). Sizes the content child to the full list and the panel
-- to min(content, SEG_MAX_H) so a long list scrolls instead of running off-screen.
function DM:PopulateSegmentMenu(W)
    local s = W.segMenu
    if not s then return end
    local db = self.db
    local ar, ag, ab = KE:GetAccentColor()
    local viewW = SEG_W - 2
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
    if list and #list > 0 then
        for i = 1, #list do
            local sdata = list[i]
            if sdata then
                local sid = sdata.sessionID
                local label = self:SafeSessionName(sdata.name)
                local dur = select(1, self.FormatDeathTime(sdata.durationSeconds))
                place(label .. "  |cff999999(" .. dur .. ")|r", W._curSessionID == sid, sid, nil)
                hadSessions = true
            end
        end
    end

    if hadSessions then
        s.divider:ClearAllPoints()
        s.divider:SetPoint("TOPLEFT", s.content, "TOPLEFT", SEG_PAD, y - 1)
        s.divider:SetSize(rowW, SEG_DIV_H)
        s.divider:Show()
        y = y - (SEG_DIV_H + 2 + SEG_ROW_GAP)
    else
        s.divider:Hide()
    end

    -- Live Current / Overall: active when nothing is pinned AND the type matches the
    -- window's resolved per-context config. All plain enum compares.
    local cfg = self:ResolveWindowConfig(W.idx)
    for _, sType in ipairs(SEGMENT_SESSION_TYPES) do
        local label = (self.SESSION_TYPE_NAMES and self.SESSION_TYPE_NAMES[sType]) or "Unknown"
        local active = (W._curSessionID == nil and cfg ~= nil and cfg.SessionType == sType)
        place(label, active, nil, sType)
    end

    -- Hide any leftover pooled rows from a longer previous list.
    for i = idx + 1, #rows do rows[i]:Hide() end

    local contentH = (-y) - SEG_ROW_GAP + SEG_PAD
    if contentH < rowH then contentH = rowH end
    s.content:SetHeight(contentH)
    local panelH = contentH + 2
    if panelH > SEG_MAX_H then panelH = SEG_MAX_H end
    s:SetSize(SEG_W, panelH)
    s.view:SetVerticalScroll(0)
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
