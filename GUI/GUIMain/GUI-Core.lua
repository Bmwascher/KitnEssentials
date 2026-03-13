-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- GUIFrame namespace for the configuration window
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
local C_Timer = C_Timer
local math_min = math.min

local Theme = KE.Theme

-- Content registration
GUIFrame.registeredContent = {}

function GUIFrame:RegisterContent(id, buildFunc)
    if type(buildFunc) ~= "function" then return end
    self.registeredContent[id] = buildFunc
end

function GUIFrame:HasContent(id)
    return self.registeredContent[id] ~= nil
end

-- Content cleanup callbacks
GUIFrame.contentCleanupCallbacks = {}

function GUIFrame:RegisterContentCleanup(key, callback)
    if type(key) == "string" and type(callback) == "function" then
        self.contentCleanupCallbacks[key] = callback
    end
end

function GUIFrame:UnregisterContentCleanup(key)
    if key then self.contentCleanupCallbacks[key] = nil end
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

-- Toggle the GUI window
function GUIFrame:Toggle()
    if InCombatLockdown() then
        KE:Print("Cannot open settings in combat.")
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
    end
end

-- Hide the GUI
function GUIFrame:Hide()
    if self.mainFrame then
        self.mainFrame:Hide()
    end
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
        self.sidebar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], T.bgMedium[4])
    end

    -- Content area
    if frame.content then
        frame.content:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    end

    -- Refresh sidebar visuals
    self:RefreshSidebar()
end

--------------------------------------------------------------------------------
-- Card System
--------------------------------------------------------------------------------
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

    function card:UpdateHeight()
        local totalHeight = self.headerHeight + self.currentY + T.paddingMedium * 2
        self:SetHeight(totalHeight)
        self.contentHeight = totalHeight
    end

    function card:GetContentHeight()
        return self.contentHeight
    end

    function card:SetEnabled(enabled)
        if enabled then
            self:SetAlpha(1)
            if self.header then self.header:SetAlpha(1) end
            if self.titleText then self.titleText:SetAlpha(1) end
        else
            self:SetAlpha(0.5)
            if self.header then self.header:SetAlpha(0.5) end
            if self.titleText then self.titleText:SetAlpha(0.5) end
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
        self:SetHeight(self.headerHeight + T.paddingMedium * 2)
    end

    card:UpdateHeight()
    return card
end

--------------------------------------------------------------------------------
-- Row System
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- RefreshContent - loads registered content for the selected sidebar item
--------------------------------------------------------------------------------
function GUIFrame:RefreshContent()
    if not self.contentArea then return end

    -- Clean up custom panel if exists (e.g. MissingBuffs sub-tab panel)
    if self.contentArea._customPanel then
        self.contentArea._customPanel:Hide()
        self.contentArea._customPanel:SetParent(nil)
        self.contentArea._customPanel = nil
    end

    -- Fire content cleanup callbacks on tab switch
    for _, callback in pairs(self.contentCleanupCallbacks) do
        pcall(callback)
    end

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
        child:Hide()
        child:SetParent(nil)
    end

    local T = Theme
    local yOffset = T.paddingMedium
    local itemId = self.selectedSidebarItem or "HomePage"

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
