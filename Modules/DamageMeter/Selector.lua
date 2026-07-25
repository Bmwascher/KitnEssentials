-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Selector.lua                                ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: In-window view-selector overlay. Right-click   ║
-- ║           the bar box -> the body is replaced by a 2x4   ║
-- ║           card grid of the 8 view types; clicking a card ║
-- ║           sets a per-window view override (Core:         ║
-- ║           SetWindowView) and keeps any pinned session    ║
-- ║           (stored or history). Mirror of Detail.lua's    ║
-- ║           in-window overlay machinery.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule
local DM = KitnEssentials:GetModule("DamageMeter")

local CreateFrame = CreateFrame
local Enum = Enum
local ipairs = ipairs
local pairs = pairs
local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local ICON = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\"

-- Card grid order is row-major over 2 columns -- index 1,2 = row 1, etc. -- so this
-- list IS the on-screen layout (the user's chosen arrangement + short labels):
--   Dmg Done            | Healing Done
--   Dmg Taken           | Enemy Dmg Taken
--   Avoidable Dmg Taken | Deaths
--   Interrupts          | Dispels
local VIEW_GRID = {
    { type = Enum.DamageMeterType.DamageDone,           label = "Dmg Done",            icon = ICON .. "dm_damage.tga" },
    { type = Enum.DamageMeterType.HealingDone,          label = "Healing Done",        icon = ICON .. "dm_healing.tga" },
    { type = Enum.DamageMeterType.DamageTaken,          label = "Dmg Taken",           icon = ICON .. "dm_dmgtaken.tga" },
    { type = Enum.DamageMeterType.EnemyDamageTaken,     label = "Enemy Dmg Taken",     icon = ICON .. "dm_enemytaken.tga" },
    { type = Enum.DamageMeterType.AvoidableDamageTaken, label = "Avoidable Dmg Taken", icon = ICON .. "dm_avoidable.tga" },
    { type = Enum.DamageMeterType.Deaths,               label = "Deaths",              icon = ICON .. "dm_deaths.tga" },
    { type = Enum.DamageMeterType.Interrupts,           label = "Interrupts",          icon = ICON .. "dm_interrupt.tga" },
    { type = Enum.DamageMeterType.Dispels,              label = "Dispels",             icon = ICON .. "dm_dispel.tga" },
}

local GRID_COLS = 2
local GRID_PAD = 4
local GRID_GAP = 3

-- Paints each card's border/bg to mark the active view. Accent border + lighter bg
-- on the active card; black border + dark bg otherwise. activeType is a plain enum.
function DM:PaintSelectorActive(W, activeType)
    if not (W.selector and W.selector.cards) then return end
    W.selector._activeType = activeType
    local ar, ag, ab = KE:GetAccentColor()
    for _, card in ipairs(W.selector.cards) do
        if card.meterType == activeType then
            card:SetBackdropBorderColor(ar or 0.6, ag or 0.6, ab or 0.6, 1)
            card:SetBackdropColor(0.16, 0.16, 0.16, 0.95)
        else
            card:SetBackdropBorderColor(0, 0, 0, 1)
            card:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
        end
    end
end

-- Re-tiles the 8 cards into a 2-column grid on the scroll content child. Called on
-- open and on the viewport's OnSizeChanged (the dock resizes the body). All plain
-- numbers; guarded against a zero/!sized viewport (first layout).
function DM:LayoutSelector(W)
    local s = W.selector
    if not s or not s.content then return end
    local w = (s.view and s.view:GetWidth()) or 0
    if w <= 0 then return end
    -- Cards use a COMFORTABLE FIXED height scaled to the font -- NEVER shrunk to the
    -- window. A window too short to show all 4 rows scrolls instead (the content child
    -- is taller than the viewport; the wheel is a no-op when everything fits). The icon
    -- is capped INDEPENDENTLY of card height so it never eats the label's width (the old
    -- height-tied square icon caused the "Dam..." truncation). Width fills the column.
    local fontSize = (self.db and self.db.FontSize) or 12
    local rows = ceil(#VIEW_GRID / GRID_COLS)
    local cardH = fontSize + 12
    local cardW = floor((w - GRID_PAD * 2 - GRID_GAP * (GRID_COLS - 1)) / GRID_COLS)
    if cardW < 1 then cardW = 1 end
    local iconSz = min(cardH - 4, fontSize + 6)
    if iconSz < 1 then iconSz = 1 end
    s.content:SetWidth(w)
    for i, card in ipairs(s.cards) do
        local col = (i - 1) % GRID_COLS
        local row = floor((i - 1) / GRID_COLS)
        local x = GRID_PAD + col * (cardW + GRID_GAP)
        local y = -(GRID_PAD + row * (cardH + GRID_GAP))
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", s.content, "TOPLEFT", x, y)
        card:SetSize(cardW, cardH)
        card.icon:SetSize(iconSz, iconSz)
    end
    -- Content height covers all rows so the viewport can scroll when the window is short.
    s.content:SetHeight(GRID_PAD * 2 + rows * cardH + (rows - 1) * GRID_GAP)
end

-- One view card: [icon] label, flat backdrop, click -> SetWindowView (left) or close
-- (right, a "back" gesture). Built once (pool reuse) per window in EnsureSelector; W
-- is captured so the click knows its window. Hover brightens; leave restores the
-- active-state paint.
local function MakeViewCard(parent, W, def)
    local db = DM.db
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
    card:SetBackdropBorderColor(0, 0, 0, 1)
    card.meterType = def.type

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetTexture(def.icon)
    card.icon:SetPoint("LEFT", card, "LEFT", 2, 0)

    card.label = card:CreateFontString(nil, "OVERLAY")
    card.label:SetPoint("LEFT", card.icon, "RIGHT", 3, 0)
    card.label:SetPoint("RIGHT", card, "RIGHT", -3, 0)
    card.label:SetJustifyH("LEFT")
    card.label:SetWordWrap(false)
    -- Card label two notches below the bar font (compact picker text); tight icon
    -- insets (left + icon->label gap) maximize label room. ReapplyBarVisuals mirrors.
    KE:ApplyFontToText(card.label, db and db.FontFace, max(8, (db and db.FontSize or 12) - 2), db and db.FontOutline)
    card.label:SetText(def.label)

    card:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            DM:CloseSelector(W)
        else
            DM:SetWindowView(W, def.type)
        end
    end)
    card:SetScript("OnEnter", function(c) c:SetBackdropColor(0.20, 0.20, 0.20, 0.95) end)
    card:SetScript("OnLeave", function() DM:PaintSelectorActive(W, W.selector and W.selector._activeType) end)
    return card
end

-- Lazily build W.selector: a container over the body (same anchors as W.detail) with a
-- scroll viewport + content child holding the 8 view cards. Idempotent. Right-click
-- (or a background click on a gap / empty area) closes -- the view + content don't
-- capture mouse, so those clicks fall through to the container; cards handle their own.
-- Frame level above the bars so it covers them; the body is hidden on open.
function DM:EnsureSelector(W)
    if W.selector then return W.selector end
    local s = CreateFrame("Frame", nil, W.frame)
    s:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -(W._headerH or 18))
    s:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", 0, 0)
    s:SetFrameLevel(W.frame:GetFrameLevel() + 4)
    s:EnableMouse(true)
    s:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then DM:CloseSelector(W) end
    end)
    s:Hide()

    -- Scroll viewport + content child (mirrors Detail.lua:EnsureDetail). Cards live on
    -- the content at a comfortable fixed size; a short window scrolls instead of
    -- shrinking them. The wheel is a no-op when the content fits the viewport.
    s.view = CreateFrame("ScrollFrame", nil, s)
    s.view:SetAllPoints(s)
    s.content = CreateFrame("Frame", nil, s.view)
    s.content:SetSize(1, 1)
    s.view:SetScrollChild(s.content)
    s.view:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then s.content:SetWidth(w) end
        DM:LayoutSelector(W)
    end)
    s.view:EnableMouseWheel(true)
    s.view:SetScript("OnMouseWheel", function(self, delta)
        local viewH = self:GetHeight() or 0
        local contentH = s.content:GetHeight() or 0
        local maxScroll = contentH - viewH
        if maxScroll <= 0 then self:SetVerticalScroll(0); return end
        local step = ((DM.db and DM.db.FontSize) or 12) + 12   -- ~one card per notch
        local new = (self:GetVerticalScroll() or 0) - delta * step
        if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)

    s.cards = {}
    for i = 1, #VIEW_GRID do
        s.cards[i] = MakeViewCard(s.content, W, VIEW_GRID[i])
    end

    W.selector = s
    return s
end

-- Show the selector over the bar box. Closes the detail panel first (defensive --
-- they share the body area), hides the hover tip + body, lays the grid out, and
-- highlights the window's current effective view. Safe to call in combat (cards are
-- static icons/labels -- no secret read).
function DM:OpenSelector(W)
    if not W then return end
    if W._detailOpen and self.CloseDetail then self:CloseDetail(W) end
    if W._segMenuOpen and self.CloseSegmentMenu then self:CloseSegmentMenu(W) end
    if self.HideHoverTip then self:HideHoverTip() end
    self:EnsureSelector(W)
    W._selectorOpen = true
    if self.SyncHeaderIconsToOverlayState then self:SyncHeaderIconsToOverlayState(W) end
    if W.body then W.body:Hide() end
    W.selector:Show()
    self:LayoutSelector(W)
    if W.selector.view then W.selector.view:SetVerticalScroll(0) end   -- open at the top
    local cfg = self:ResolveWindowConfig(W.idx)
    self:PaintSelectorActive(W, self:EffectiveMeterType(W.idx, cfg))
end

function DM:CloseSelector(W)
    if not W or not W.selector then return end
    W._selectorOpen = false
    W.selector:Hide()
    if W.body then W.body:Show() end
    if self.SyncHeaderIconsToOverlayState then self:SyncHeaderIconsToOverlayState(W) end
end

-- Close any open selector across every window. Called from the module's teardown /
-- segment-boundary paths (combat start, context auto-swap, reset, EditMode/lock) so an
-- open selector never leaves W.body hidden once the live bars should be showing -- the
-- parity the detail panel already gets from its CloseDetail hooks. Idempotent + nil-safe.
function DM:CloseAllSelectors()
    if not self.windows_rt then return end
    for _, W in pairs(self.windows_rt) do
        if W._selectorOpen then self:CloseSelector(W) end
    end
end

-- Right-click dispatcher for the bar box (wired in Window.lua from the bars' OnClick
-- and the body catcher). Right-click is "back / menu": close an open detail panel,
-- else close an open selector, else open the selector.
function DM:OnWindowRightClick(W)
    if not W then return end
    if W._detailOpen then
        if self.CloseDetail then self:CloseDetail(W) end
        return
    end
    if W._selectorOpen then
        self:CloseSelector(W)
        return
    end
    self:OpenSelector(W)
end
