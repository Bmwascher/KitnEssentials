-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KESubTabs.lua                                       ║
-- ║  Purpose: Reusable horizontal sub-tab bar for tabbed     ║
-- ║           module GUI pages.                              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local ipairs = ipairs
local C_Timer = C_Timer
local wipe = wipe

-- File-local debounce: rapid tab clicks (e.g. clicking through every tab in a
-- single frame) can race against RefreshContent's teardown/build cycle and
-- leave the tab row partially rendered. Collapse multiple clicks within the
-- same frame into a single end-of-frame refresh.
local refreshScheduled = false

local function ScheduleRefresh()
    if refreshScheduled then return end
    refreshScheduled = true
    C_Timer.After(0, function()
        refreshScheduled = false
        if GUIFrame.RefreshContent then
            GUIFrame:RefreshContent()
        end
    end)
end

local TAB_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local function PaintTab(btn, active)
    local T, a = Theme, Theme.accent
    btn._bar:SetShown(active)
    if active then
        -- Opaque over the window color, so a strip on a card panel reads the
        -- same as one on the window.
        btn:SetBackdropColor(KE.BlendColor(a, 0.20, T.bgDark))
        btn:SetBackdropBorderColor(a[1], a[2], a[3], 0.8)
        btn._bar:SetColorTexture(a[1], a[2], a[3], 1)
        btn.label:SetTextColor(a[1], a[2], a[3], 1)
    else
        local idle, idleEdge = T.controlBg, T.controlBorder
        btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
        btn:SetBackdropBorderColor(idleEdge[1], idleEdge[2], idleEdge[3], 1)
        -- Full white for inactive tabs: a dim gray reads as washed-out on
        -- dark backdrops, and accent-on-active vs white-on-inactive gives
        -- clearer contrast. Hover state uses the backdrop tint for
        -- differentiation, not text alpha.
        btn.label:SetTextColor(1, 1, 1, 1)
    end
end

-- The strip's per-use state (active tab, switch handler) lives on the strip,
-- so every tab button's scripts are set once and read it when they run.
local function TabOnClick(b)
    -- First, so a click on the tab already on screen also keeps this page.
    GUIFrame:DropQueuedPage()
    local strip = b._strip
    if b.tabId == strip._activeId then return end
    local onSwitch = strip._onSwitch
    if onSwitch then onSwitch(b.tabId) end
    ScheduleRefresh()
end

local function TabOnEnter(b)
    if b.tabId ~= b._strip._activeId then
        b:SetBackdropColor(KE.BlendColor(Theme.accent, 0.12, Theme.controlBg))
        b.label:SetTextColor(1, 1, 1, 1)
    end
end

local function TabOnLeave(b)
    if b.tabId ~= b._strip._activeId then
        local idle = Theme.controlBg
        b:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
        b.label:SetTextColor(1, 1, 1, 1)
    end
end

-- A fill strip sizes each tab to its label and leaves the row's remaining
-- width empty.
local function SizeTabToText(btn)
    local width = (btn.label:GetStringWidth() or 0) + Theme.paddingLarge * 2
    btn:SetWidth(width)
    return width
end

function GUIFrame.SubTabOffset(widths, index, spacing)
    local x = 0
    for i = 1, index - 1 do
        x = x + widths[i] + spacing
    end
    return x
end

-- Re-measured a frame after layout: a FontString can report short before its
-- first layout pass, and there is no distributed slack to absorb a bad
-- measurement. Each pass clears before it anchors, because setting the same
-- point again does not give back a position the client has dropped.
local function PlaceFillTabs(strip)
    if not strip._fill then return end
    local tabs, widths, spacing = strip._tabButtons, strip._tabWidths, strip._spacing
    local count = strip._count
    for i = 1, count do
        widths[i] = SizeTabToText(tabs[i])
    end
    for i = 1, count do
        local tab = tabs[i]
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", strip, "TOPLEFT", GUIFrame.SubTabOffset(widths, i, spacing), 0)
    end
end

-- OnSizeChanged runs inside the client's layout, where a moved tab can be
-- left with no position, so a resize, a show and a build only queue one pass
-- for the next frame.
local function QueuePlaceFillTabs(strip)
    if strip._placeQueued then return end
    strip._placeQueued = true
    C_Timer.After(0, strip._placeNext)
end

-- Tab buttons are made as a page first needs them and kept; a strip reused by
-- a page with fewer tabs hides the spare ones.
local function NewTab(strip)
    local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
    btn:SetBackdrop(TAB_BACKDROP)
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    btn.label = label
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetHeight(2)
    bar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
    bar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    bar:Hide()
    btn._bar = bar
    btn._strip = strip
    btn:SetScript("OnClick", TabOnClick)
    btn:SetScript("OnEnter", TabOnEnter)
    btn:SetScript("OnLeave", TabOnLeave)
    local tabs = strip._tabButtons
    tabs[#tabs + 1] = btn
    GUIFrame:PoolGrow(strip, strip, 1, 0)
    return btn
end

local function ConstructSubTabs(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip._tabButtons = {}
    strip._tabWidths = {}
    strip.buttons = {}
    strip._count = 0
    -- Made once per strip, so a resize drag allocates nothing per frame.
    strip._placeQueued = false
    strip._placeNext = function()
        strip._placeQueued = false
        PlaceFillTabs(strip)
    end
    strip:SetScript("OnSizeChanged", QueuePlaceFillTabs)
    -- A reopen shows the old page without a build.
    strip:SetScript("OnShow", QueuePlaceFillTabs)
    strip._keOwned = { strip }
    return strip
end

local subTabPool = GUIFrame:NewWidgetPool("subtabs", ConstructSubTabs, function() end)

---------------------------------------------------------------------------------
-- Sub-tab widget
---------------------------------------------------------------------------------
-- Usage:
--   local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
--       tabs = {
--           { id = "General", label = "General" },
--           { id = "Windows", label = "Windows" },
--       },
--       activeId = currentTab,
--       onSwitch = function(newId)
--           currentTab = newId
--       end,
--       tabWidth = 120,  -- optional, default 120 (ignored when fill = true)
--       fill = false,    -- optional, when true each tab is sized to its own label
--   })
--
-- onSwitch is called BEFORE the frame refresh schedules; callers only need to
-- update their state. The widget handles RefreshContent internally.
--
-- Returns: (container frame, new yOffset after the sub-tab row)
function GUIFrame:CreateSubTabs(parent, yOffset, config)
    config = config or {}
    local tabs = config.tabs or {}
    local tabWidth = config.tabWidth or 120
    local tabHeight = config.tabHeight or 28
    local spacing = config.spacing or 1
    local fill = config.fill == true
    local activeId = config.activeId

    local T = Theme

    local strip
    if self:IsPoolParent(parent) then
        strip = subTabPool:Acquire(parent)
    else
        strip = ConstructSubTabs(parent)
    end
    strip:ClearAllPoints()
    strip:SetHeight(tabHeight)
    strip:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -yOffset)
    strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.paddingSmall, -yOffset)
    strip._activeId = activeId
    strip._onSwitch = config.onSwitch
    strip._fill = fill
    strip._spacing = spacing

    local buttons = strip.buttons
    wipe(buttons)
    local btnList = strip._tabButtons

    for i, def in ipairs(tabs) do
        local btn = btnList[i] or NewTab(strip)
        btn:ClearAllPoints()
        btn:SetHeight(tabHeight)

        -- A fill tab is sized and placed after the loop, once every label is set.
        if not fill then
            btn:SetSize(tabWidth, tabHeight)
            btn:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * (tabWidth + spacing), 0)
        end

        KE:ApplyThemeFont(btn.label, "normal")
        btn.label:SetText(def.label or def.id)
        btn.tabId = def.id
        PaintTab(btn, def.id == activeId)
        btn:Show()

        buttons[def.id] = btn
    end

    for i = #tabs + 1, #btnList do
        btnList[i]:Hide()
    end
    strip._count = #tabs

    if fill and #tabs > 0 then
        -- Placed now as well as after layout, so a new strip never draws a
        -- frame of zero-width or unplaced tabs.
        PlaceFillTabs(strip)
        QueuePlaceFillTabs(strip)
    end

    return strip, yOffset + tabHeight + T.paddingSmall
end

GUIFrame.HEALER_VIEW_TABS = {
    { id = "DEFAULT", label = "Default" },
    { id = "HEALER",  label = "Healer" },
}
