-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Sidebar.lua                                         ║
-- ║  Purpose: Sidebar navigation with collapsible sections   ║
-- ║  and search.                                             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local math = math
local ipairs = ipairs
local type = type
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local wipe = wipe
local C_Timer = C_Timer
local table_insert = table.insert
local strtrim = strtrim
local GameTooltip = GameTooltip

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- Sidebar state
GUIFrame.sidebarHeaderPool = {}
GUIFrame.staticSidebarItemPool = {}
GUIFrame.sidebarExpanded = {}
GUIFrame.selectedSidebarItem = nil
GUIFrame.sidebarRefreshPending = false

local headerHeight = 32
local itemHeight = 28

local PROFILER_FOOTER_HEIGHT = 58
-- Without the mode line the block reclaims its reserved row and the scroll
-- region above grows by the same amount. Safe to size on that state because it
-- is latched at profiler load and cannot change without a reload.
local PROFILER_FOOTER_HEIGHT_COMPACT = 43
local PROFILER_REFRESH_SECONDS = 5

local PROFILER_TOOLTIP_COMMON = "Blizzard's always-on rolling 60-tick KitnEssentials CPU average. The percentage is an estimate of the current frame budget at your present FPS, not the profiler reset window."
local PROFILER_TOOLTIP_ACTIVE = "Detailed profiling is active. It unlocks reset-window and named-frame diagnostics but adds overhead; disable it when testing is finished."
local PROFILER_TOOLTIP_INACTIVE = "Detailed profiling is inactive for this UI load. Use /kes profiler on, then /reload, to enable reset-window and named-frame diagnostics."

---------------------------------------------------------------------------------
-- Section Rendering
---------------------------------------------------------------------------------
function GUIFrame:ReleaseSectionHeaders()
    for _, header in ipairs(self.sidebarHeaderPool or {}) do
        header.inUse = false
        header.disabled = nil
        header:Hide()
        header:ClearAllPoints()
    end
end

function GUIFrame:CreateSectionHeader()
    local T = Theme
    local header = CreateFrame("Button", nil, UIParent)
    header:SetHeight(headerHeight)
    header:EnableMouse(true)
    header:RegisterForClicks("LeftButtonUp")

    -- Hover overlay (gradient)
    local background = header:CreateTexture(nil, "ARTWORK")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, 1)
    background:SetGradient("HORIZONTAL", CreateColor(0.3, 0.3, 0.3, 0.25), CreateColor(0.3, 0.3, 0.3, 0))
    background:SetTexelSnappingBias(0)
    background:SetSnapToPixelGrid(false)
    background:Hide()
    header.background = background

    -- Selected overlay
    local selectedOverlay = header:CreateTexture(nil, "ARTWORK")
    selectedOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    selectedOverlay:SetBlendMode("ADD")
    selectedOverlay:SetVertexColor(T.selectedBg[1], T.selectedBg[2], T.selectedBg[3], T.selectedBg[4] or 0.35)
    selectedOverlay:SetAllPoints()
    selectedOverlay:Hide()
    header.selectedOverlay = selectedOverlay

    -- Left accent bar
    local selectedBar = header:CreateTexture(nil, "OVERLAY")
    selectedBar:SetWidth(3)
    selectedBar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    selectedBar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    selectedBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    selectedBar:Hide()
    header.selectedBar = selectedBar

    -- Label
    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", header, "LEFT", T.paddingSmall, 0)
    KE:ApplyThemeFont(label, "large")
    label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    label:SetShadowColor(0, 0, 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    header.label = label

    -- Arrow icon (texture with rotation animation)
    local arrowTex = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse"
    local ARROW_SIZE = 16
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("RIGHT", header, "RIGHT", -(T.paddingSmall + 10), 0)
    arrow:SetTexture(arrowTex)
    arrow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    header.arrow = arrow

    -- Animation setup
    local arrowAnimGroup = arrow:CreateAnimationGroup()
    local arrowRotation = arrowAnimGroup:CreateAnimation("Rotation")
    arrowRotation:SetDuration(0.18)
    arrowRotation:SetOrigin("CENTER", 0, 0)
    arrowRotation:SetSmoothing("IN_OUT")
    header.arrowAnimGroup = arrowAnimGroup
    header.arrowRotation = arrowRotation

    header.SetArrowState = function(self, expanded, animate)
        if animate then
            if expanded and not self.isExpanded then
                self.arrowAnimGroup:Stop()
                self.arrow:SetRotation(-math.pi / 2)
                self.arrowRotation:SetRadians(math.pi / 2)
                self.isExpanded = true
                self.arrowAnimGroup:Play()
                arrowAnimGroup:SetScript("OnFinished", function()
                    self.arrow:SetRotation(0)
                end)
            elseif not expanded and self.isExpanded then
                self.arrowAnimGroup:Stop()
                self.arrow:SetRotation(0)
                self.arrowRotation:SetRadians(-math.pi / 2)
                self.isExpanded = false
                self.arrowAnimGroup:Play()
                arrowAnimGroup:SetScript("OnFinished", function()
                    self.arrow:SetRotation(-math.pi / 2)
                end)
            end
        else
            self.arrowAnimGroup:Stop()
            if expanded then
                self.arrow:SetRotation(0)
            else
                self.arrow:SetRotation(-math.pi / 2)
            end
            self.isExpanded = expanded
        end
    end

    -- Hover effects
    header:SetScript("OnEnter", function(self)
        if not self.isExpanded then
            background:Show()
        end
    end)

    header:SetScript("OnLeave", function(self)
        if not self.isExpanded then
            background:Hide()
        end
    end)

    -- Click handler
    header:SetScript("OnClick", function(self)
        GUIFrame:ToggleSection(self.sectionId)
    end)

    return header
end

function GUIFrame:GetSectionHeader()
    for _, header in ipairs(self.sidebarHeaderPool) do
        if not header.inUse then
            header.inUse = true
            header:Show()
            return header
        end
    end

    local header = self:CreateSectionHeader()
    header.inUse = true
    table_insert(self.sidebarHeaderPool, header)
    return header
end

function GUIFrame:ConfigureSectionHeader(header, config, yOffset, isExpanded)
    local T = Theme
    local scrollChild = self.sidebar.scrollChild

    header:SetParent(scrollChild)
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -yOffset)
    header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -T.paddingSmall, -yOffset)
    -- Reset to enabled — the sidebar filter path (BuildSidebar) sets
    -- EnableMouse(false) on headers while filtering. Without this reset,
    -- pooled headers reused after a filter clear stay click-disabled.
    header:EnableMouse(true)
    header.sectionId = config.id
    header.label:SetText(config.text or "")

    -- Grey out if disabled (ElvUI check or custom disabledCheck function)
    local isDisabled = false
    if config.elvUIDisabled and KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() then
        isDisabled = true
    elseif config.disabledCheck and type(config.disabledCheck) == "function" then
        isDisabled = config.disabledCheck()
    end

    if isDisabled then
        header.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.35)
        header.arrow:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.35)
        header.disabled = true
    else
        header.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        header.arrow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        header.selectedBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        header.disabled = false
    end

    header:SetArrowState(isExpanded)
    header.background:Hide()
    return header
end

function GUIFrame:GetHeaderBySectionId(sectionId)
    for _, header in ipairs(self.sidebarHeaderPool) do
        if header.inUse and header.sectionId == sectionId then
            return header
        end
    end
end

---------------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------------
local sidebarInitialized = false
function GUIFrame:InitializeSidebarExpansion()
    if sidebarInitialized then return end
    wipe(self.sidebarExpanded)

    for _, section in ipairs(self.sidebarConfig) do
        if section.type == "header" and section.defaultExpanded then
            local sectionOff = (section.elvUIDisabled and KE.ShouldNotLoadModule and KE:ShouldNotLoadModule())
                or (section.disabledCheck and type(section.disabledCheck) == "function" and section.disabledCheck())
            if sectionOff then
                self.sidebarExpanded[section.id] = nil
            else
                self.sidebarExpanded[section.id] = true
            end
        end
    end
    sidebarInitialized = true
end

---------------------------------------------------------------------------------
-- Toggle Section
---------------------------------------------------------------------------------
function GUIFrame:ToggleSection(sectionId)
    if self.sidebarExpanded[sectionId] then
        self.sidebarExpanded[sectionId] = nil
        local header = self:GetHeaderBySectionId(sectionId)
        if header then header:SetArrowState(false, true) end
    else
        self.sidebarExpanded[sectionId] = true
        local header = self:GetHeaderBySectionId(sectionId)
        if header then header:SetArrowState(true, true) end
    end
    C_Timer.After(0.01, function()
        self:RefreshSidebar()
    end)
end

---------------------------------------------------------------------------------
-- Static Sidebar Items
---------------------------------------------------------------------------------
function GUIFrame:ReleaseStaticSidebarItems()
    for _, item in ipairs(self.staticSidebarItemPool) do
        item.inUse = false
        item:Hide()
        item:ClearAllPoints()
        item.id = nil
        item.disabled = nil
        item.selectedOverlay:Hide()
        item.selectedBar:Hide()
    end
end

function GUIFrame:CreateStaticSidebarItem()
    local T = Theme
    local r, g, b = T.accent[1], T.accent[2], T.accent[3]

    local item = CreateFrame("Button", nil, UIParent)
    item:SetHeight(itemHeight)
    item:EnableMouse(true)
    item:RegisterForClicks("LeftButtonUp")

    -- Hover overlay (gradient)
    local background = item:CreateTexture(nil, "ARTWORK")
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1, 1)
    background:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0))
    background:SetTexelSnappingBias(0)
    background:SetSnapToPixelGrid(false)
    background:Hide()
    item.background = background

    -- Selected overlay (gradient)
    local selectedOverlay = item:CreateTexture(nil, "ARTWORK")
    selectedOverlay:SetAllPoints()
    selectedOverlay:SetColorTexture(1, 1, 1, 1)
    -- Selected strength follows the theme. The item BACKGROUND gradient above
    -- carries the same literal and is the HOVER state -- leave it alone.
    selectedOverlay:SetGradient("HORIZONTAL",
        CreateColor(r, g, b, T.selectedBg[4] or 0.35), CreateColor(r, g, b, 0))
    selectedOverlay:SetTexelSnappingBias(0)
    selectedOverlay:SetSnapToPixelGrid(false)
    selectedOverlay:Hide()
    item.selectedOverlay = selectedOverlay

    -- Left accent bar
    local selectedBar = item:CreateTexture(nil, "OVERLAY")
    selectedBar:SetWidth(1)
    selectedBar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 5)
    selectedBar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, -7)
    selectedBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    selectedBar:Hide()
    item.selectedBar = selectedBar

    -- Label
    local label = item:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", item, "LEFT", 12, 0)
    label:SetPoint("RIGHT", item, "RIGHT", -T.paddingSmall, 0)
    KE:ApplyThemeFont(label, "normal")
    label:SetShadowColor(0, 0, 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    item.label = label

    -- Hover
    item:SetScript("OnEnter", function(self)
        if self.id ~= GUIFrame.selectedSidebarItem then
            background:Show()
            self.label:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end)

    item:SetScript("OnLeave", function(self)
        if self.id ~= GUIFrame.selectedSidebarItem then
            background:Hide()
            self.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        end
    end)

    -- Click
    item:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            GUIFrame:SelectSidebarItem(self.id)
        end
    end)

    return item
end

function GUIFrame:GetStaticSidebarItem()
    for _, item in ipairs(self.staticSidebarItemPool) do
        if not item.inUse then
            item.inUse = true
            item:Show()
            return item
        end
    end

    local item = self:CreateStaticSidebarItem()
    item.inUse = true
    table_insert(self.staticSidebarItemPool, item)
    return item
end

---------------------------------------------------------------------------------
-- Select Sidebar Item
---------------------------------------------------------------------------------
function GUIFrame:SelectSidebarItem(itemId)
    local T = Theme
    self.selectedSidebarItem = itemId

    -- Close hamburger menu if open
    if self.menuDropdown and self.menuDropdown:IsShown() then
        self.menuDropdown:Hide()
    end

    for _, item in ipairs(self.staticSidebarItemPool) do
        if item.inUse then
            if item.disabled then
                item.selectedOverlay:Hide()
                item.selectedBar:Hide()
            elseif item.id == itemId then
                item.selectedOverlay:Show()
                item.background:Hide()
                item.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], T.accent[4] or 1)
            else
                item.selectedOverlay:Hide()
                item.background:Hide()
                item.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
            end
        end
    end

    -- Update section-based previews
    if KE.PreviewManager then
        KE.PreviewManager:SetActivePage(itemId)
    end

    self:RefreshContent()
end

---------------------------------------------------------------------------------
-- Profiler Footer
---------------------------------------------------------------------------------
function GUIFrame:RefreshProfilerFooter()
    if not self.profilerFooter then return end

    local cpuText = "CPU: unavailable"
    local detailedEnabled = false
    local profiler = KE.Profiler
    if profiler and type(profiler.GetFooterDisplay) == "function" then
        cpuText, detailedEnabled = profiler.GetFooterDisplay()
    end

    local T = Theme
    self.profilerFooterHeader:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)
    self.profilerFooterText:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)
    self.profilerFooterModeText:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

    if self._profilerFooterCpuText ~= cpuText then
        self._profilerFooterCpuText = cpuText
        self.profilerFooterText:SetText(cpuText)
    end

    if self.profilerFooterDetailedEnabled ~= detailedEnabled then
        self.profilerFooterDetailedEnabled = detailedEnabled
        -- The CPU line normally stacks on the mode line, so shrinking the block
        -- alone would drag it up into the header. Re-anchor it to the bottom
        -- edge whenever the mode line is not there to sit on.
        self.profilerFooterText:ClearAllPoints()
        if detailedEnabled then
            self.profilerFooterModeText:Show()
            self.profilerFooterText:SetPoint("BOTTOMLEFT", self.profilerFooterModeText, "TOPLEFT", 0, 1)
            self.profilerFooterText:SetPoint("BOTTOMRIGHT", self.profilerFooterModeText, "TOPRIGHT", 0, 1)
            self.profilerFooter:SetHeight(PROFILER_FOOTER_HEIGHT)
        else
            self.profilerFooterModeText:Hide()
            self.profilerFooterText:SetPoint("BOTTOMLEFT", self.profilerFooter, "BOTTOMLEFT", T.paddingSmall, T.paddingSmall)
            self.profilerFooterText:SetPoint("BOTTOMRIGHT", self.profilerFooter, "BOTTOMRIGHT", -T.paddingSmall, T.paddingSmall)
            self.profilerFooter:SetHeight(PROFILER_FOOTER_HEIGHT_COMPACT)
        end
    end
end

---------------------------------------------------------------------------------
-- Sidebar Creation
---------------------------------------------------------------------------------
function GUIFrame:CreateSidebar(parent)
    local T = Theme

    local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", T.borderSize, -(T.headerHeight + T.borderSize))
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", T.borderSize, T.footerHeight)
    sidebar:SetWidth(T.sidebarWidth)
    sidebar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    -- A light tint over the window's own fill, not a fill of its own: 0.40 is
    -- the value the sidebar reads at against the single-fill body.
    sidebar:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.40)

    -- Right border
    local rightBorder = sidebar:CreateTexture(nil, "BORDER")
    rightBorder:SetWidth(T.borderSize)
    rightBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    rightBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Search bar (fixed above scroll area)
    local SEARCH_HEIGHT = 24
    local searchContainer = CreateFrame("Frame", nil, sidebar, "BackdropTemplate")
    searchContainer:SetHeight(SEARCH_HEIGHT)
    searchContainer:SetPoint("TOPLEFT", sidebar, "TOPLEFT", T.paddingSmall, -T.paddingSmall)
    searchContainer:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -(T.paddingSmall + T.borderSize), -T.paddingSmall)
    searchContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    searchContainer:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    searchContainer:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Search EditBox
    local searchEditBox = CreateFrame("EditBox", nil, searchContainer)
    searchEditBox:SetPoint("LEFT", searchContainer, "LEFT", 6, 0)
    searchEditBox:SetPoint("RIGHT", searchContainer, "RIGHT", -22, 0)
    searchEditBox:SetPoint("TOP", searchContainer, "TOP", 0, -3)
    searchEditBox:SetPoint("BOTTOM", searchContainer, "BOTTOM", 0, 3)
    searchEditBox:SetFont(KE:GetFontPath("Expressway"), T.fontSizeSmall, T.fontOutline or "OUTLINE")
    searchEditBox:SetAutoFocus(false)
    searchEditBox:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    searchEditBox:SetMaxLetters(50)

    -- Placeholder text
    local placeholder = searchContainer:CreateFontString(nil, "OVERLAY")
    placeholder:SetPoint("LEFT", searchContainer, "LEFT", 6, 0)
    KE:ApplyThemeFont(placeholder, "small")
    placeholder:SetText("Search...")
    placeholder:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.4)

    -- Clear button (X)
    local clearBtn = CreateFrame("Button", nil, searchContainer)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", searchContainer, "RIGHT", -4, 0)
    local clearIcon = clearBtn:CreateTexture(nil, "ARTWORK")
    clearIcon:SetAllPoints()
    clearIcon:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png")
    clearIcon:SetRotation(math.rad(45))
    clearIcon:SetVertexColor(1, 1, 1, 1)
    clearBtn:Hide()

    -- Placeholder/clear button visibility
    local function UpdateSearchVisuals()
        if searchEditBox:GetText() == "" then
            placeholder:Show()
            clearBtn:Hide()
        else
            placeholder:Hide()
            clearBtn:Show()
        end
    end

    -- Real-time filtering
    searchEditBox:SetScript("OnTextChanged", function(self, userInput)
        UpdateSearchVisuals()
        GUIFrame.searchFilter = strtrim(self:GetText()):lower()
        GUIFrame:RefreshSidebar()
    end)

    searchEditBox:SetScript("OnEditFocusGained", function()
        searchContainer:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)

    searchEditBox:SetScript("OnEditFocusLost", function()
        local L = KE.Theme
        searchContainer:SetBackdropBorderColor(L.border[1], L.border[2], L.border[3], 1)
    end)

    searchEditBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    clearBtn:SetScript("OnClick", function()
        searchEditBox:SetText("")
        searchEditBox:ClearFocus()
    end)

    clearBtn:SetScript("OnEnter", function()
        local L = KE.Theme
        clearIcon:SetVertexColor(L.accent[1], L.accent[2], L.accent[3], 1)
    end)

    clearBtn:SetScript("OnLeave", function()
        clearIcon:SetVertexColor(1, 1, 1, 1)
    end)

    GUIFrame.searchEditBox = searchEditBox
    GUIFrame.searchContainer = searchContainer

    -- Profiler footer (fixed height, above the version/resize bottom bar)
    local profilerFooter = CreateFrame("Frame", nil, sidebar)
    profilerFooter:SetHeight(PROFILER_FOOTER_HEIGHT)
    profilerFooter:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 0)
    profilerFooter:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -T.borderSize, 0)
    profilerFooter:EnableMouse(true)

    local profilerFooterHeader = profilerFooter:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(profilerFooterHeader, "small")
    profilerFooterHeader:SetPoint("TOPLEFT", profilerFooter, "TOPLEFT", T.paddingSmall, -T.paddingSmall)
    profilerFooterHeader:SetPoint("TOPRIGHT", profilerFooter, "TOPRIGHT", -T.paddingSmall, -T.paddingSmall)
    profilerFooterHeader:SetJustifyH("CENTER")
    profilerFooterHeader:SetWordWrap(false)
    profilerFooterHeader:SetText("All KitnEssentials")

    local separatorHolder = CreateFrame("Frame", nil, profilerFooter)
    separatorHolder:SetHeight(6)
    separatorHolder:SetPoint("TOPLEFT", profilerFooterHeader, "BOTTOMLEFT", 0, -1)
    separatorHolder:SetPoint("TOPRIGHT", profilerFooterHeader, "BOTTOMRIGHT", 0, -1)
    local profilerFooterSeparator = GUIFrame:CreateSeparator(separatorHolder)

    local profilerFooterModeText = profilerFooter:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(profilerFooterModeText, "small")
    profilerFooterModeText:SetPoint("BOTTOMLEFT", profilerFooter, "BOTTOMLEFT", T.paddingSmall, T.paddingSmall)
    profilerFooterModeText:SetPoint("BOTTOMRIGHT", profilerFooter, "BOTTOMRIGHT", -T.paddingSmall, T.paddingSmall)
    profilerFooterModeText:SetJustifyH("CENTER")
    profilerFooterModeText:SetWordWrap(false)
    profilerFooterModeText:SetText("Detailed profiler: ON")

    local profilerFooterText = profilerFooter:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(profilerFooterText, "small")
    profilerFooterText:SetPoint("BOTTOMLEFT", profilerFooterModeText, "TOPLEFT", 0, 1)
    profilerFooterText:SetPoint("BOTTOMRIGHT", profilerFooterModeText, "TOPRIGHT", 0, 1)
    profilerFooterText:SetJustifyH("CENTER")
    profilerFooterText:SetWordWrap(false)

    GUIFrame.profilerFooter = profilerFooter
    GUIFrame.profilerFooterHeader = profilerFooterHeader
    GUIFrame.profilerFooterSeparator = profilerFooterSeparator
    GUIFrame.profilerFooterText = profilerFooterText
    GUIFrame.profilerFooterModeText = profilerFooterModeText

    profilerFooter:SetScript("OnEnter", function(self)
        local L = Theme
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("All KitnEssentials", L.accent[1], L.accent[2], L.accent[3], 1)
        GameTooltip:AddLine(PROFILER_TOOLTIP_COMMON, 1, 1, 1, true)
        if GUIFrame.profilerFooterDetailedEnabled then
            GameTooltip:AddLine(PROFILER_TOOLTIP_ACTIVE, 1, 1, 1, true)
        else
            GameTooltip:AddLine(PROFILER_TOOLTIP_INACTIVE, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    profilerFooter:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    scrollFrame:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    scrollFrame:SetPoint("TOPLEFT", searchContainer, "BOTTOMLEFT", -T.paddingSmall, -T.paddingSmall)
    scrollFrame:SetPoint("BOTTOMRIGHT", profilerFooter, "TOPRIGHT", 0, 0)
    scrollFrame:SetClipsChildren(true)

    -- Hide default scrollbar
    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -2, -16)
        sb:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -2, 16)
        sb:SetWidth(10)
        if sb.Background then sb.Background:Hide() end
        if sb.Top then sb.Top:Hide() end
        if sb.Middle then sb.Middle:Hide() end
        if sb.Bottom then sb.Bottom:Hide() end
        if sb.trackBG then sb.trackBG:Hide() end
        if sb.ScrollUpButton then sb.ScrollUpButton:Hide() end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetAlpha(0)
    end

    -- Smooth mousewheel scrolling
    local SIDEBAR_SCROLL_STEP = 30
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if scrollFrame.ScrollBar then
            local sb = scrollFrame.ScrollBar
            local current = sb:GetValue()
            local minVal, maxVal = sb:GetMinMaxValues()
            local newValue = current - (delta * SIDEBAR_SCROLL_STEP)
            if newValue < minVal then newValue = minVal end
            if newValue > maxVal then newValue = maxVal end
            sb:SetValue(newValue)
        end
    end)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollChild:SetWidth(1)
    scrollChild:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Update scrollChild width when sidebar resizes (sidebar width is dynamic)
    local function UpdateSidebarScrollChildWidth()
        local w = sidebar:GetWidth()
        if w and w > 0 then
            scrollChild:SetWidth(w - T.borderSize)
        end
    end
    sidebar:HookScript("OnSizeChanged", UpdateSidebarScrollChildWidth)
    C_Timer.After(0, UpdateSidebarScrollChildWidth)

    -- Auto-show/hide scrollbar
    local function UpdateScrollBarVisibility()
        if scrollFrame.ScrollBar then
            local contentH = scrollChild:GetHeight()
            local frameH = scrollFrame:GetHeight()
            local needsScrollbar = contentH > frameH
            scrollFrame.ScrollBar:SetAlpha(needsScrollbar and 1 or 0)
            scrollFrame.ScrollBar:EnableMouse(needsScrollbar)
        end
    end
    scrollFrame:HookScript("OnScrollRangeChanged", UpdateScrollBarVisibility)
    scrollChild:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)

    sidebar.scrollFrame = scrollFrame
    sidebar.scrollChild = scrollChild
    parent.sidebar = sidebar
    self.sidebar = sidebar

    local function StopProfilerFooterTicker()
        if GUIFrame.profilerFooterTicker then
            GUIFrame.profilerFooterTicker:Cancel()
            GUIFrame.profilerFooterTicker = nil
        end
    end

    sidebar:HookScript("OnShow", function()
        StopProfilerFooterTicker()
        GUIFrame:RefreshProfilerFooter()
        GUIFrame.profilerFooterTicker = C_Timer.NewTicker(PROFILER_REFRESH_SECONDS, function()
            GUIFrame:RefreshProfilerFooter()
        end)
    end)
    sidebar:HookScript("OnHide", StopProfilerFooterTicker)

    GUIFrame:RefreshProfilerFooter()

    return sidebar
end

---------------------------------------------------------------------------------
-- Search match helper
---------------------------------------------------------------------------------
-- Returns true if an item matches the (already-lowercased) search term by its
-- title text or any of its optional lowercase `keywords`. Used by RefreshSidebar.
local function ItemMatches(itemConfig, term)
    if itemConfig.text and itemConfig.text:lower():find(term, 1, true) then
        return true
    end
    if type(itemConfig.keywords) == "table" then
        for _, kw in ipairs(itemConfig.keywords) do
            if kw:find(term, 1, true) then
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------------------------
-- Refresh Sidebar
---------------------------------------------------------------------------------
function GUIFrame:RefreshSidebar()
    if not self.sidebar then return end
    local T = Theme

    self:ReleaseStaticSidebarItems()
    self:ReleaseSectionHeaders()

    local scrollChild = self.sidebar.scrollChild
    local config = self.sidebarConfig
    if not config then
        scrollChild:SetHeight(1)
        return
    end

    local yOffset = T.paddingSmall
    local itemSpacing = 2
    local sectionSpacing = 2
    local itemIndent = 8

    local filter = self.searchFilter or ""
    local isFiltering = filter ~= ""

    for _, sectionConfig in ipairs(config) do
        if sectionConfig.type == "header" then
            -- Filter items when searching
            local visibleItems = sectionConfig.items
            local skipSection = false

            if isFiltering and sectionConfig.items then
                -- A section-name match (>=2 chars) reveals the whole section;
                -- otherwise filter to items matching their title or keywords.
                local sectionTextLower = sectionConfig.text and sectionConfig.text:lower()
                local sectionMatch = #filter >= 2
                    and sectionTextLower
                    and sectionTextLower:find(filter, 1, true)
                if sectionMatch then
                    visibleItems = sectionConfig.items -- shared reference, read-only below
                else
                    visibleItems = {}
                    for _, itemConfig in ipairs(sectionConfig.items) do
                        if ItemMatches(itemConfig, filter) then
                            visibleItems[#visibleItems + 1] = itemConfig
                        end
                    end
                    if #visibleItems == 0 then
                        skipSection = true
                    end
                end
            end

            if not skipSection then
                -- Force expand when filtering, normal toggle otherwise
                local isExpanded = isFiltering or self.sidebarExpanded[sectionConfig.id]
                local header = self:GetSectionHeader()
                self:ConfigureSectionHeader(header, sectionConfig, yOffset, isExpanded)

                -- Disable collapse toggle while filtering
                if isFiltering then
                    header:EnableMouse(false)
                end

                yOffset = yOffset + headerHeight

                if isExpanded and visibleItems then
                    local sectionDisabled = (sectionConfig.elvUIDisabled and KE.ShouldNotLoadModule and KE:ShouldNotLoadModule())
                        or (sectionConfig.disabledCheck and type(sectionConfig.disabledCheck) == "function" and sectionConfig.disabledCheck())

                    for _, itemConfig in ipairs(visibleItems) do
                        local item = self:GetStaticSidebarItem()
                        item:SetParent(scrollChild)
                        item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall + itemIndent, -yOffset)
                        item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -T.paddingSmall, -yOffset)
                        item.id = itemConfig.id
                        item.label:SetText(itemConfig.text or "")
                        item.selectedBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
                        item.selectedBar:Show()
                        item.selectedOverlay:SetColorTexture(1, 1, 1, 1)
                        item.selectedOverlay:SetGradient("HORIZONTAL",
                            CreateColor(T.accent[1], T.accent[2], T.accent[3], T.selectedBg[4] or 0.35),
                            CreateColor(T.accent[1], T.accent[2], T.accent[3], 0))
                        item.background:SetColorTexture(1, 1, 1, 1)
                        item.background:SetGradient("HORIZONTAL",
                            CreateColor(T.accent[1], T.accent[2], T.accent[3], 0.25),
                            CreateColor(T.accent[1], T.accent[2], T.accent[3], 0))

                        if sectionDisabled and not itemConfig.alwaysEnabled then
                            item.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.35)
                            item.selectedOverlay:Hide()
                            item.selectedBar:Hide()
                            item:EnableMouse(false)
                            item.disabled = true
                        else
                            item.disabled = false
                            item:EnableMouse(true)
                            if itemConfig.id == self.selectedSidebarItem then
                                item.selectedOverlay:Show()
                                item.background:Hide()
                                item.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], T.accent[4] or 1)
                            else
                                item.selectedOverlay:Hide()
                                item.background:Hide()
                                item.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                            end
                        end
                        yOffset = yOffset + itemHeight + itemSpacing
                    end
                end
                yOffset = yOffset + sectionSpacing
            end
        end
    end

    -- "No results" message when filtering produces nothing
    if isFiltering and yOffset <= T.paddingSmall + sectionSpacing then
        if not scrollChild._noResultsText then
            local noResults = scrollChild:CreateFontString(nil, "OVERLAY")
            KE:ApplyThemeFont(noResults, "normal")
            noResults:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.5)
            noResults:SetText("No results found")
            scrollChild._noResultsText = noResults
        end
        scrollChild._noResultsText:ClearAllPoints()
        scrollChild._noResultsText:SetPoint("TOP", scrollChild, "TOP", 0, -(yOffset + 20))
        scrollChild._noResultsText:Show()
        yOffset = yOffset + 50
    else
        if scrollChild._noResultsText then
            scrollChild._noResultsText:Hide()
        end
    end

    scrollChild:SetHeight(yOffset + T.paddingSmall)
end

---------------------------------------------------------------------------------
-- OpenPage
---------------------------------------------------------------------------------
function GUIFrame:OpenPage(itemId, sectionId, context)
    self.pendingContext = context
    self:Show()
    if sectionId then
        self.sidebarExpanded[sectionId] = true
        self:RefreshSidebar()
    end
    self:SelectSidebarItem(itemId)
end
