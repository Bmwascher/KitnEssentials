-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local math = math
local ipairs = ipairs
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local wipe = wipe
local C_Timer = C_Timer
local table_insert = table.insert

-- Sidebar state
GUIFrame.sidebarHeaderPool = {}
GUIFrame.staticSidebarItemPool = {}
GUIFrame.sidebarExpanded = {}
GUIFrame.selectedSidebarItem = nil
GUIFrame.sidebarRefreshPending = false

local headerHeight = 32
local itemHeight = 28

--------------------------------------------------------------------------------
-- Section Header Pool
--------------------------------------------------------------------------------
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
    selectedOverlay:SetVertexColor(T.selectedBg[1], T.selectedBg[2], T.selectedBg[3], T.selectedBg[4] or 0.25)
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
    header.sectionId = config.id
    header.label:SetText(config.text or "")

    -- Grey out if ElvUI-disabled
    if config.elvUIDisabled and KE.ShouldNotLoadModule and KE:ShouldNotLoadModule() then
        header.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.35)
        header.arrow:SetVertexColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 0.35)
        header.disabled = true
    else
        header.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        header.arrow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
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

--------------------------------------------------------------------------------
-- Initialize sidebar expansion from defaults
--------------------------------------------------------------------------------
local sidebarInitialized = false
function GUIFrame:InitializeSidebarExpansion()
    if sidebarInitialized then return end
    wipe(self.sidebarExpanded)

    for _, section in ipairs(self.sidebarConfig) do
        if section.type == "header" and section.defaultExpanded then
            self.sidebarExpanded[section.id] = true
        end
    end
    sidebarInitialized = true
end

--------------------------------------------------------------------------------
-- Toggle Section
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Static Sidebar Items (child items under sections)
--------------------------------------------------------------------------------
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
    selectedOverlay:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.25), CreateColor(r, g, b, 0))
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

--------------------------------------------------------------------------------
-- Select Sidebar Item
--------------------------------------------------------------------------------
function GUIFrame:SelectSidebarItem(itemId)
    local T = Theme
    self.selectedSidebarItem = itemId

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

    self:RefreshContent()
end

--------------------------------------------------------------------------------
-- Create Sidebar
--------------------------------------------------------------------------------
function GUIFrame:CreateSidebar(parent)
    local T = Theme

    local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", T.borderSize, -(T.headerHeight + T.borderSize))
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", T.borderSize, T.footerHeight)
    sidebar:SetPoint("RIGHT", parent.content or parent, "LEFT", 0, 0)
    sidebar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    sidebar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4])

    -- Right border
    local rightBorder = sidebar:CreateTexture(nil, "BORDER")
    rightBorder:SetWidth(T.borderSize)
    rightBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    rightBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    rightBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], T.border[4])

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    scrollFrame:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -T.paddingSmall)
    scrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -T.borderSize, T.paddingSmall)
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
    return sidebar
end

--------------------------------------------------------------------------------
-- Refresh Sidebar
--------------------------------------------------------------------------------
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

    for _, sectionConfig in ipairs(config) do
        if sectionConfig.type == "header" then
            local isExpanded = self.sidebarExpanded[sectionConfig.id]
            local header = self:GetSectionHeader()
            self:ConfigureSectionHeader(header, sectionConfig, yOffset, isExpanded)
            yOffset = yOffset + headerHeight

            if isExpanded and sectionConfig.items then
                local sectionDisabled = sectionConfig.elvUIDisabled and KE.ShouldNotLoadModule and KE:ShouldNotLoadModule()

                for _, itemConfig in ipairs(sectionConfig.items) do
                    local item = self:GetStaticSidebarItem()
                    item:SetParent(scrollChild)
                    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall + itemIndent, -yOffset)
                    item:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -T.paddingSmall, -yOffset)
                    item.id = itemConfig.id
                    item.label:SetText(itemConfig.text or "")
                    item.selectedBar:Show()

                    if sectionDisabled then
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

    scrollChild:SetHeight(yOffset + T.paddingSmall)
end

--------------------------------------------------------------------------------
-- OpenPage - programmatic navigation
--------------------------------------------------------------------------------
function GUIFrame:OpenPage(itemId, sectionId, context)
    self.pendingContext = context
    self:Show()
    if sectionId then
        self.sidebarExpanded[sectionId] = true
        self:RefreshSidebar()
    end
    self:SelectSidebarItem(itemId)
end
