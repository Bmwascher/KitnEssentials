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
    if active then
        btn:SetBackdropColor(a[1], a[2], a[3], 0.25)
        btn:SetBackdropBorderColor(a[1], a[2], a[3], 0.8)
        btn.label:SetTextColor(a[1], a[2], a[3], 1)
    else
        btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 0.6)
        btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4] or 0.4)
        -- Full white for inactive tabs — accent-on-active vs
        -- white-on-inactive gives clearer contrast than the previous
        -- gray (0.6 alpha) which read as washed-out on dark
        -- backdrops. Hover state uses the backdrop tint for
        -- differentiation, not text alpha.
        btn.label:SetTextColor(1, 1, 1, 1)
    end
end

-- The strip's per-use state (active tab, switch handler) lives on the strip,
-- so every tab button's scripts are set once and read it when they run.
local function TabOnClick(b)
    local strip = b._strip
    if b.tabId == strip._activeId then return end
    local onSwitch = strip._onSwitch
    if onSwitch then onSwitch(b.tabId) end
    ScheduleRefresh()
end

local function TabOnEnter(b)
    if b.tabId ~= b._strip._activeId then
        local a = Theme.accent
        b:SetBackdropColor(a[1], a[2], a[3], 0.12)
        b.label:SetTextColor(1, 1, 1, 1)
    end
end

local function TabOnLeave(b)
    if b.tabId ~= b._strip._activeId then
        local T = Theme
        b:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4] or 0.6)
        b.label:SetTextColor(1, 1, 1, 1)
    end
end

-- The row's remaining width is left empty. Measured at layout time rather
-- than at creation: a FontString can report short before its first layout
-- pass, and there is no longer any distributed slack to absorb a bad
-- measurement.
local function SizeTabsToText(strip)
    if not strip._fill then return end
    local tabPadding = Theme.paddingLarge * 2
    local tabs = strip._tabButtons
    for i = 1, strip._count do
        local btn = tabs[i]
        btn:SetWidth((btn.label:GetStringWidth() or 0) + tabPadding)
    end
end

-- Tab buttons are made as a page first needs them and kept; a strip reused by
-- a page with fewer tabs hides the spare ones.
local function NewTab(strip)
    local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
    btn:SetBackdrop(TAB_BACKDROP)
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    btn.label = label
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
    strip.buttons = {}
    strip._count = 0
    strip:SetScript("OnSizeChanged", SizeTabsToText)
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
    strip._count = #tabs

    local buttons = strip.buttons
    wipe(buttons)
    local btnList = strip._tabButtons

    for i, def in ipairs(tabs) do
        local btn = btnList[i] or NewTab(strip)
        btn:ClearAllPoints()
        btn:SetHeight(tabHeight)

        if fill then
            -- TOPLEFT chains left to right; each width comes from that tab's
            -- own label in the sizing pass.
            if i == 1 then
                btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
            else
                btn:SetPoint("TOPLEFT", btnList[i - 1], "TOPRIGHT", spacing, 0)
            end
        else
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

    if fill and #tabs > 0 then
        C_Timer.After(0, function() SizeTabsToText(strip) end)
    end

    return strip, yOffset + tabHeight + T.paddingSmall
end
