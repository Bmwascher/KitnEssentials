-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Core.lua                                            ║
-- ║  Purpose: Core GUI framework — frame creation,           ║
-- ║  show/hide, theme initialization.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local GUIFrame = {}
KE.GUIFrame = GUIFrame

local type = type
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local wipe = wipe
local CreateFrame = CreateFrame
local table_insert = table.insert

local Theme = KE.Theme

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------

-- Content registration
GUIFrame.registeredContent = {}

function GUIFrame:RegisterContent(id, buildFunc)
    if type(buildFunc) ~= "function" then return end
    self.registeredContent[id] = buildFunc
end

function GUIFrame:HasContent(id)
    return self.registeredContent[id] ~= nil
end

-- Panel registration (full content area takeover, no scroll frame)
GUIFrame.PanelBuilders = {}

function GUIFrame:RegisterPanel(itemId, builderFunc)
    if type(builderFunc) ~= "function" then return end
    self.PanelBuilders[itemId] = builderFunc
end

function GUIFrame:HasPanel(itemId)
    return self.PanelBuilders[itemId] ~= nil
end

-- Content cleanup callbacks (fire on REAL item switch only — used by modules
-- that need to tear down preview state, etc.)
GUIFrame.contentCleanupCallbacks = {}

function GUIFrame:RegisterContentCleanup(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentCleanupCallbacks[key] = callback
    end
end

function GUIFrame:UnregisterContentCleanup(key)
    if key then self.contentCleanupCallbacks[key] = nil end
end

-- Content rebuild callbacks (fire UNCONDITIONALLY at the start of every
-- RefreshContent — used by widget pools to ReleaseAll before the new render
-- starts so kits can be re-acquired into the fresh scrollChild without
-- being orphaned by ClearContent's SetParent(nil) loop).
GUIFrame.contentRebuildCallbacks = {}

function GUIFrame:RegisterContentRebuildCallback(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentRebuildCallbacks[key] = callback
    end
end

function GUIFrame:UnregisterContentRebuildCallback(key)
    if key then self.contentRebuildCallbacks[key] = nil end
end

-- Refresh a pool kit's theme-tied colors lazily — only on the first Configure
-- after KE:RefreshTheme bumped the theme version. Each kit caches the version
-- it was last refreshed at; mismatch triggers card-level + widget-level
-- ApplyThemeColors. Pools call this from their Configure path; non-pool
-- callers (which build cards from scratch each render) pick up the new
-- palette implicitly so they never need this helper.
function GUIFrame:RefreshKitThemeIfNeeded(kit, widgets)
    local v = (KE._themeVersion or 0)
    if kit._themeVersion == v then return end
    if kit.card and kit.card.ApplyThemeColors then
        kit.card:ApplyThemeColors()
    end
    -- widgets param overrides the kit-level convention; fall back to
    -- kit.themeWidgets which factories can set once.
    widgets = widgets or kit.themeWidgets
    if widgets then
        for _, w in ipairs(widgets) do
            if w and w.ApplyThemeColors then w:ApplyThemeColors() end
        end
    end
    kit._themeVersion = v
end

-- On-close callbacks
GUIFrame.onCloseCallbacks = {}

function GUIFrame:RegisterOnCloseCallback(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.onCloseCallbacks[key] = callback
    end
end

function GUIFrame:FireOnCloseCallbacks()
    for _, callback in pairs(self.onCloseCallbacks) do
        pcall(callback)
    end
end

---------------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------------

-- Toggle the GUI window
function GUIFrame:Toggle()
    -- The window can never be on screen during combat, so the only thing a
    -- toggle can flip is whether it will be open once combat ends.
    if InCombatLockdown() then
        if self.reopenAfterCombat then
            self.reopenAfterCombat = nil
            KE:Print("Options window will stay closed after combat.")
        else
            self.reopenAfterCombat = true
            KE:Print("Options will open after combat ends.")
        end
        return
    end
    if self.mainFrame and self.mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if GUI is currently shown
function GUIFrame:IsShown()
    return self.mainFrame and self.mainFrame:IsShown()
end

-- Show the GUI
function GUIFrame:Show()
    if InCombatLockdown() then
        KE:Print("Options will open after combat ends.")
        self.reopenAfterCombat = true
        return
    end
    if not self.mainFrame then
        self:CreateMainFrame()
    end
    self.mainFrame:Show()
    KE.GUIOpen = true
    if KE.PreviewManager then
        KE.PreviewManager:SetGUIOpen(true)
    end
    -- Initialize sidebar and show default page on first open
    if not self.selectedSidebarItem then
        self:InitializeSidebarExpansion()
        self:RefreshSidebar()
        self:SelectSidebarItem("HomePage")
    elseif self._contentDirtyWhileHidden then
        -- A refresh was requested while hidden (RefreshContent's hidden gate
        -- swallowed it) — replay it once so the reopened page isn't stale.
        self:RefreshContent()
    end
end

-- Collapse the window to its title bar, so in-world elements stay reachable
-- without losing the page being worked on. Drag handlers live on the main
-- frame, which stays shown, so a collapsed window still moves. Saved height
-- lives on the table rather than the frame so a hide/show cycle cannot lose it.
--
-- The resize minimum has to drop with it: the next layout pass would otherwise
-- clamp the frame straight back up to the full minimum height.
function GUIFrame:ToggleMinimize()
    local frame = self.mainFrame
    if not frame then return end
    self.minimized = not self.minimized

    if self.minimized then
        self._savedHeight = frame:GetHeight()
        if self.contentArea then self.contentArea:Hide() end
        if self.sidebar then self.sidebar:Hide() end
        if self.bottomBar then self.bottomBar:Hide() end
        local collapsed = Theme.headerHeight + Theme.borderSize * 2
        frame:SetResizeBounds(self.minWidth, collapsed)
        frame:SetHeight(collapsed)
    else
        -- Height first, then the bound. Raising the minimum while the frame is
        -- still collapsed clamps it to that minimum and fires an extra size
        -- pass on the way back up.
        frame:SetHeight(self._savedHeight or self.minHeight)
        frame:SetResizeBounds(self.minWidth, self.minHeight)
        if self.contentArea then self.contentArea:Show() end
        if self.sidebar then self.sidebar:Show() end
        if self.bottomBar then self.bottomBar:Show() end

        -- RefreshContent refuses to rebuild while collapsed, so the page can be
        -- stale by the time it comes back — an edit-mode drag writes positions
        -- the sliders never saw.
        if self._contentDirtyWhileHidden then
            self:RefreshContent()
        end
    end

    if self.PaintMinimizeArrow then self:PaintMinimizeArrow() end
end

-- Hide the GUI
function GUIFrame:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
    -- Clear search on close
    if self.searchEditBox then
        self.searchEditBox:SetText("")
        self.searchEditBox:ClearFocus()
    end
    self.searchFilter = ""
    -- Fire cleanup
    for _, callback in pairs(self.contentCleanupCallbacks) do
        pcall(callback)
    end
    self:FireOnCloseCallbacks()
    KE.GUIOpen = false
    if KE.PreviewManager then
        KE.PreviewManager:SetGUIOpen(false)
    end
end

---------------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------------

-- Apply theme colors to all GUI elements
function GUIFrame:ApplyThemeColors()
    if not self.mainFrame then return end
    local T = Theme
    local frame = self.mainFrame

    -- Main frame
    frame:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Sidebar
    if self.sidebar then
        self.sidebar:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.40)
    end

    -- Content area
    if frame.content then
        frame.content:SetBackdropColor(0, 0, 0, 0)
    end

    -- Refresh sidebar visuals
    self:RefreshSidebar()

    -- Search bar
    if self.searchContainer then
        self.searchContainer:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
        self.searchContainer:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    end
    if self.searchEditBox then
        self.searchEditBox:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end

    -- Update title and version text with new accent color
    if self.titleText then
        self.titleText:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials")
    end
    if self.versionText then
        self.versionText:SetText(KE:ColorTextByTheme("Kitn") .. "Essentials |cff888888v" .. (KE.Version or "?") .. "|r")
    end

    -- Rebuild current content to pick up new accent colors
    if self.selectedSidebarItem then
        self:RefreshContent()
    end
end

---------------------------------------------------------------------------------
-- Card System
---------------------------------------------------------------------------------
function GUIFrame:CreateCard(parent, title, yOffset, width)
    local T = Theme
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:EnableMouse(false)

    if width then
        card:SetWidth(width)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
        card:SetPoint("RIGHT", parent, "RIGHT", -T.paddingSmall, 0)
    end

    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = T.borderSize,
    })
    card:SetBackdropColor(T.bgLight[1], T.bgLight[2], T.bgLight[3], T.bgLight[4])
    card:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])

    card.contentHeight = 0
    card.rows = {}
    card._yOffset = yOffset or 0

    -- Header
    local headerHeight = 0
    if title and title ~= "" then
        headerHeight = 32

        local header = CreateFrame("Frame", nil, card, "BackdropTemplate")
        header:SetHeight(headerHeight)
        header:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        header:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = T.borderSize,
        })
        header:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4])
        header:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], T.border[4])
        card.header = header

        local titleText = header:CreateFontString(nil, "OVERLAY")
        titleText:SetPoint("LEFT", header, "LEFT", T.paddingMedium, 0)
        KE:ApplyThemeFont(titleText, "large")
        titleText:SetText(title)
        titleText:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        card.titleText = titleText
    end

    -- Header toggle: the MODULE-ENABLE control. A switch in the card's title
    -- bar reads as "this feature on/off"; everything in the body below is
    -- settings. Keeps enables visually distinct from ordinary option toggles,
    -- which live in body rows.
    function card:AddHeaderToggle(initialState, onValueChanged)
        if not self.header then return nil end
        local TRACK_W, TRACK_H, KNOB = 34, 16, 12

        local btn = CreateFrame("Button", nil, self.header, "BackdropTemplate")
        btn:SetSize(TRACK_W, TRACK_H)
        btn:SetPoint("LEFT", self.titleText, "RIGHT", 12, 0)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = KE:GetPixelSize(),
        })
        btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

        local knob = btn:CreateTexture(nil, "ARTWORK")
        knob:SetSize(KNOB, KNOB)

        local function Paint(on)
            knob:ClearAllPoints()
            if on then
                btn:SetBackdropColor(T.accent[1] * 0.5, T.accent[2] * 0.5, T.accent[3] * 0.5, 1)
                knob:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
                knob:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.8)
            else
                btn:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
                knob:SetPoint("LEFT", btn, "LEFT", 2, 0)
                knob:SetColorTexture(0.45, 0.45, 0.45, 1)
            end
        end

        btn._checked = initialState and true or false
        Paint(btn._checked)

        function btn:SetChecked(on)
            self._checked = on and true or false
            Paint(self._checked)
        end
        function btn:GetChecked() return self._checked end

        btn:SetScript("OnClick", function(b)
            b:SetChecked(not b._checked)
            if onValueChanged then onValueChanged(b._checked) end
            -- A disabled module renders as a lone header bar, so the page must
            -- rebuild here for that to apply immediately.
            GUIFrame:RefreshContent()
            GUIFrame:RefreshSidebar()
        end)
        btn:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText(b._checked and "Enabled" or "Disabled", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        self.headerToggle = btn
        return btn
    end

    card.headerHeight = headerHeight

    -- Content container
    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT", card, "TOPLEFT", T.paddingMedium, -headerHeight - T.paddingMedium)
    content:SetPoint("TOPRIGHT", card, "TOPRIGHT", -T.paddingMedium, -headerHeight - T.paddingMedium)
    content:SetHeight(1)
    content:EnableMouse(false)
    card.content = content
    card.currentY = 0

    function card:AddRow(widget, height, spacing)
        height = height or widget:GetHeight() or 24
        spacing = spacing or T.paddingSmall
        widget:SetParent(self.content)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
        widget:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        self.currentY = self.currentY + height + spacing
        table_insert(self.rows, widget)
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return widget
    end

    function card:AddLabel(text)
        local label = self.content:CreateFontString(nil, "OVERLAY")
        label:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY)
        label:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        label:SetJustifyH("LEFT")
        KE:ApplyThemeFont(label, "normal")
        label:SetText(text)
        label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        local height = label:GetStringHeight() or 14
        self.currentY = self.currentY + height + T.paddingSmall
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return label
    end

    -- A label with the accent-coloured lead-in the GUI uses for explanatory
    -- text. Resolved per call, not captured, so it follows a theme change.
    function card:AddNote(text)
        return self:AddLabel(KE:ColorTextByTheme("-") .. " " .. text)
    end

    function card:AddSeparator()
        local sep = self.content:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(T.borderSize)
        sep:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.currentY - T.paddingSmall)
        sep:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY - T.paddingSmall)
        sep:SetColorTexture(T.border[1], T.border[2], T.border[3], 0.5)
        self.currentY = self.currentY + T.borderSize + T.paddingSmall * 2
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
        return sep
    end

    function card:AddSpacing(amount)
        amount = amount or T.paddingMedium
        self.currentY = self.currentY + amount
        self.content:SetHeight(self.currentY)
        self:UpdateHeight()
    end

    -- Header-only collapse: a card with no body rows or labels — a module whose
    -- only control is its header toggle, or any module rendered as a lone header
    -- bar while disabled — is just its title bar. Without this branch the card
    -- still reserves paddingMedium*2 of empty body beneath the header, which
    -- reads as a stray gap between it and the next card.
    function card:UpdateHeight()
        local totalHeight
        if self.currentY == 0 and self.headerHeight > 0 then
            -- Exactly the header, so the header plate covers the card entirely
            -- and the bar is one solid colour. No borderSize*2 allowance: the
            -- header is flush at (0,0) with its own edge, so that allowance
            -- would expose two pixels of card backdrop under the header.
            totalHeight = self.headerHeight
            self.content:Hide()
        else
            totalHeight = self.headerHeight + self.currentY + T.paddingMedium * 2
            self.content:Show()
        end
        self:SetHeight(totalHeight)
        self.contentHeight = totalHeight
    end

    function card:GetContentHeight()
        return self.contentHeight
    end

    function card:GetNextOffset()
        return self._yOffset + self:GetContentHeight() + Theme.paddingSmall
    end

    -- Lazy-create a transparent click-blocker overlay above the card content.
    -- Shown when the card is disabled to make widget interactions non-functional
    -- without recursively walking row.widgets / kit subframes (which would need
    -- per-widget knowledge of how each card type lays out its children).
    local function GetMouseBlocker(c)
        if c._mouseBlocker then return c._mouseBlocker end
        local blocker = CreateFrame("Frame", nil, c)
        blocker:SetAllPoints(c)
        -- +100 above the card's own frame level should cover all default-level
        -- descendants. Cards don't generally bump child frame levels.
        blocker:SetFrameLevel(c:GetFrameLevel() + 100)
        blocker:EnableMouse(true)
        -- Don't capture mouse wheel — let scroll events bubble up to the
        -- scrollFrame so the user can still scroll past a disabled card.
        blocker:Hide()
        c._mouseBlocker = blocker
        return blocker
    end

    function card:SetEnabled(enabled)
        if enabled then
            self:SetAlpha(1)
            if self.header then self.header:SetAlpha(1) end
            if self.titleText then self.titleText:SetAlpha(1) end
            if self._mouseBlocker then self._mouseBlocker:Hide() end
        else
            self:SetAlpha(0.5)
            if self.header then self.header:SetAlpha(0.5) end
            if self.titleText then self.titleText:SetAlpha(0.5) end
            GetMouseBlocker(self):Show()
        end
    end

    -- Re-apply theme-tied colors. KE:RefreshTheme replaces Theme.bgLight /
    -- accent / border tables via CopyColor; values copied at construction
    -- (SetBackdropColor, SetTextColor) become stale. Pool-reused cards keep
    -- the old palette across renders unless this is called. Pool Configures
    -- invoke this; non-pooled callers (which rebuild the card per render)
    -- pick up the new palette implicitly so calling here is harmless.
    function card:ApplyThemeColors()
        local TT = Theme
        self:SetBackdropColor(TT.bgLight[1], TT.bgLight[2], TT.bgLight[3], TT.bgLight[4])
        self:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], TT.border[4])
        if self.header then
            self.header:SetBackdropColor(TT.bgMedium[1], TT.bgMedium[2], TT.bgMedium[3], TT.bgMedium[4])
            self.header:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], TT.border[4])
        end
        if self.titleText then
            self.titleText:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        end
    end

    function card:Reset()
        for _, row in ipairs(self.rows) do
            if row.Hide then row:Hide() end
            if row.SetParent then row:SetParent(nil) end
        end
        wipe(self.rows)
        self.currentY = 0
        self.contentHeight = 0
        self.content:SetHeight(1)
        -- One source of truth for card height; a reset card has no rows, so this
        -- resolves to the header-only collapse above.
        self:UpdateHeight()
    end

    card:UpdateHeight()
    return card
end

---------------------------------------------------------------------------------
-- Row System
---------------------------------------------------------------------------------
function GUIFrame:CreateRow(parent, height)
    local T = Theme
    height = height or 24
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    row:EnableMouse(false)
    row.widgets = {}
    row.nextX = 0

    function row:AddWidget(widget, widthPct, spacing, xOffset, yOffset)
        widthPct = widthPct or 0.5
        spacing = spacing or T.paddingSmall
        xOffset = xOffset or 0
        yOffset = yOffset or 0
        widget:SetParent(self)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", self.nextX + xOffset, yOffset)
        if not widget.explicitHeight then
            widget:SetHeight(height)
        end
        widget._widthPct = widthPct
        widget._spacing = spacing
        widget._xOffset = xOffset
        widget._yOffset = yOffset
        table_insert(self.widgets, widget)
        self.nextX = self.nextX + 10
    end

    row:SetScript("OnSizeChanged", function(self, width)
        local x = 0
        for _, widget in ipairs(self.widgets) do
            local widgetWidth = width * widget._widthPct - (widget._spacing or 0)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", self, "TOPLEFT", x + (widget._xOffset or 0), widget._yOffset or 0)
            widget:SetWidth(widgetWidth)
            x = x + widgetWidth + (widget._spacing or T.paddingSmall)
        end
    end)

    return row
end

---------------------------------------------------------------------------------
-- RefreshContent
---------------------------------------------------------------------------------
function GUIFrame:RefreshContent()
    -- Leak tracer: every call increments a /run-readable global so a runaway
    -- rebuild loop can be detected and its page named live, without a debug
    -- build:
    --   /run print(KE_GUI_REFRESH_COUNT, KE_GUI_REFRESH_ITEM, KE_GUI_ORPHAN_COUNT)
    -- Counts ABOVE the contentArea guard on purpose: a pre-first-open call is
    -- still a caller worth catching. Cost is one add + two writes per call.
    KE_GUI_REFRESH_COUNT = (KE_GUI_REFRESH_COUNT or 0) + 1
    KE_GUI_REFRESH_ITEM = self.selectedSidebarItem or "HomePage"

    if not self.contentArea then return end

    -- NEVER rebuild while the GUI is hidden. The clear pass below orphans a full
    -- page of cards via SetParent(nil), and frames are never garbage-collected --
    -- an event-driven caller firing with the GUI closed (shipped example:
    -- Automation's CVAR_UPDATE handler) leaks hundreds of permanent frames per
    -- event, unbounded, and reached hundreds of thousands in one session. Mark
    -- dirty and bail; Show() replays one refresh so a reopened page is never
    -- stale.
    -- Minimized counts as hidden here. The frame is still shown, so the test
    -- below passes, but the page is not on screen and every edit-mode drop
    -- calls in — which is the same unbounded orphaning this guard exists to
    -- stop, just reached by a different door.
    if self.minimized or not (self.mainFrame and self.mainFrame:IsShown()) then
        self._contentDirtyWhileHidden = true
        return
    end
    self._contentDirtyWhileHidden = nil

    -- Fire rebuild callbacks FIRST so widget pools can ReleaseAll their
    -- kits back to their hidden holders before the SetParent(nil) loop
    -- below would orphan them. Always fires regardless of in-place vs.
    -- item-switch — pools need to release every render, not just on
    -- item changes.
    for _, callback in pairs(self.contentRebuildCallbacks) do
        pcall(callback)
    end

    -- In-place refresh detection: when the same panel is being rebuilt
    -- (e.g. RefreshContentDeferred fired by a card edit on the DungeonTimers
    -- panel), skip the teardown side effects (cleanup callbacks, panel
    -- OnHide preview teardown). Otherwise the live preview stops + restarts
    -- across the rebuild and the user sees a visible bar/text flash on every
    -- keystroke. Cleared at the end of this function before the next call.
    local itemId = self.selectedSidebarItem or "HomePage"
    local sameItem = (self.contentArea._lastItemId == itemId)
    self.contentArea._inPlaceRefresh = sameItem

    -- Clean up custom panel if exists (e.g. sub-tab panel)
    if self.contentArea._customPanel then
        self.contentArea._customPanel:Hide()
        self.contentArea._customPanel:SetParent(nil)
        self.contentArea._customPanel = nil
    end

    -- Fire content cleanup callbacks ONLY on real item switch — same-item
    -- refreshes shouldn't tear down preview state.
    if not sameItem then
        for _, callback in pairs(self.contentCleanupCallbacks) do
            pcall(callback)
        end
    end

    -- Flag is only needed across the synchronous teardown above (panel
    -- :Hide() fires OnHide handlers in-place). Clear before the new panel
    -- is built; record the itemId so the next RefreshContent can detect
    -- in-place vs. switch.
    self.contentArea._inPlaceRefresh = false
    self.contentArea._lastItemId = itemId

    -- Show scroll frame
    if self.contentArea.scrollFrame then
        self.contentArea.scrollFrame:Show()
    end

    -- Clear existing content
    local scrollChild = self.contentArea.scrollChild

    for _, region in ipairs({ scrollChild:GetRegions() }) do
        if region:GetObjectType() == "FontString" or region:GetObjectType() == "Texture" then
            region:Hide()
        end
    end
    for _, child in ipairs({ scrollChild:GetChildren() }) do
        -- DEBUG_LEAK tracer: orphaned widget trees are permanent (frames never
        -- GC); this count is the leak's ground-truth denominator.
        KE_GUI_ORPHAN_COUNT = (KE_GUI_ORPHAN_COUNT or 0) + 1
        child:Hide()
        child:SetParent(nil)
    end

    local T = Theme
    local yOffset = T.paddingMedium

    -- Check for panel builders (full content-area takeover, no scroll frame)
    if itemId and self.PanelBuilders and self.PanelBuilders[itemId] then
        if self.contentArea.scrollFrame then
            self.contentArea.scrollFrame:Hide()
        end

        local contentFrame = self.contentArea
        local ok, panel = pcall(self.PanelBuilders[itemId], contentFrame)
        if ok and panel then
            contentFrame._customPanel = panel
        elseif not ok then
            if contentFrame.scrollFrame then
                contentFrame.scrollFrame:Show()
            end
            local errChild = contentFrame.scrollChild
            local errorCard = self:CreateCard(errChild, "Error", T.paddingMedium)
            errorCard:AddLabel("Panel builder failed: " .. tostring(panel))
        end
        return
    end

    if itemId and self.registeredContent[itemId] then
        local ok, result = pcall(self.registeredContent[itemId], scrollChild, yOffset)
        if ok and result then
            yOffset = result
        elseif ok then
            -- Builder returned nil (stub) — show placeholder
            yOffset = self:BuildPlaceholderContent(scrollChild, yOffset)
        else
            local errorCard = self:CreateCard(scrollChild, "Error", yOffset)
            errorCard:AddLabel("Content builder failed: " .. tostring(result))
            yOffset = yOffset + errorCard:GetContentHeight() + T.paddingMedium
        end
    else
        -- No registered builder
        yOffset = self:BuildPlaceholderContent(scrollChild, yOffset)
    end

    scrollChild:SetHeight(yOffset + T.paddingLarge)
end

-- Placeholder for tabs with no content builder yet
function GUIFrame:BuildPlaceholderContent(scrollChild, yOffset)
    local T = Theme
    local card = self:CreateCard(scrollChild, "Coming Soon", yOffset)
    card:AddLabel("This section is under construction.")
    card:AddSpacing(T.paddingSmall)
    yOffset = yOffset + card:GetContentHeight() + T.paddingMedium
    return yOffset
end
