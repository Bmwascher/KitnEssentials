-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KESubTabPanel.lua                                   ║
-- ║  Purpose: Top-of-page sub-tab strip with hover/click     ║
-- ║  states and a shared content area below. Used by DT      ║
-- ║  per-trigger Cfg, Bars/Texts settings, etc.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
KE.GUI = KE.GUI or {}

local CreateFrame = CreateFrame
local table_insert = table.insert
local ipairs = ipairs
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local C_Timer = C_Timer

local DEFAULT_TAB_BAR_HEIGHT = 28
local HOVER_DURATION = 0.12

function KE.GUI.CreateSubTabPanel(container, tabs, options)
    local Theme = KE.Theme
    options = options or {}
    local tabBarHeight = options.tabBarHeight or DEFAULT_TAB_BAR_HEIGHT
    local defaultTab = options.defaultTab or (tabs[1] and tabs[1].id)
    local onTabChanged = options.onTabChanged

    local currentTab = defaultTab
    local tabButtons = {}

    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()

    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetHeight(tabBarHeight)
    tabBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)

    local tabBarBorder = tabBar:CreateTexture(nil, "ARTWORK")
    tabBarBorder:SetHeight(1)
    tabBarBorder:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    tabBarBorder:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabBarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -1)
    contentFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local contentArea = KE.GUI.CreateBasicContentArea(contentFrame, {
        contentWidth = options.contentWidth or Theme.contentWidth,
        showBackground = false,
        scrollbarOptions = {
            width = 16,
            thumbHeight = 40,
            padding = { top = -2, bottom = -1, right = 0 },
            scrollStep = 40,
            anchorToScrollFrame = true,
        },
    })

    local scrollFrame = contentArea.scrollFrame
    local scrollChild = contentArea.scrollChild
    local scrollbar = contentArea.scrollbar

    local function UpdateTabVisuals()
        for _, btn in ipairs(tabButtons) do
            if btn.tabId == currentTab then
                btn.label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                btn.underline:Show()
                btn.selectedOverlay:Show()
            else
                btn.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                btn.underline:Hide()
                btn.selectedOverlay:Hide()
            end
        end
    end

    local minPadding = Theme.paddingMedium * 2
    local totalTextWidth = 0
    for i, tabDef in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetHeight(tabBarHeight)
        btn.tabId = tabDef.id
        btn.tabIndex = i

        local hoverBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hoverBg:SetAllPoints()
        hoverBg:SetColorTexture(1, 1, 1, 0.05)
        hoverBg:SetAlpha(0)
        btn.hoverBg = hoverBg

        local selectedOverlay = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        selectedOverlay:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.08)
        selectedOverlay:Hide()
        btn.selectedOverlay = selectedOverlay

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        if KE.ApplyThemeFont then
            KE:ApplyThemeFont(label, "small")
        else
            label:SetFontObject("GameFontNormalSmall")
        end
        label:SetText(tabDef.text)
        label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn.textWidth = textWidth
        totalTextWidth = totalTextWidth + textWidth

        local underline = btn:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        underline:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        underline:Hide()
        btn.underline = underline

        btn.hoverTarget = 0

        btn:SetScript("OnUpdate", function(self, elapsed)
            local current = hoverBg:GetAlpha()
            if math_abs(current - self.hoverTarget) > 0.01 then
                local speed = elapsed / HOVER_DURATION
                if self.hoverTarget > current then
                    hoverBg:SetAlpha(math_min(current + speed, self.hoverTarget))
                else
                    hoverBg:SetAlpha(math_max(current - speed, self.hoverTarget))
                end
            end
        end)

        btn:SetScript("OnEnter", function(self)
            self.hoverTarget = 1
            if currentTab ~= self.tabId then
                self.label:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            self.hoverTarget = 0
            if currentTab ~= self.tabId then
                self.label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
            end
        end)

        btn:SetScript("OnClick", function(self)
            if currentTab ~= self.tabId then
                currentTab = self.tabId
                UpdateTabVisuals()
                if onTabChanged then
                    onTabChanged(currentTab)
                end
            end
        end)

        table_insert(tabButtons, btn)
    end

    local function LayoutTabs(barWidth)
        if barWidth <= 0 then return end
        local numTabs = #tabButtons
        local totalMinWidth = totalTextWidth + (minPadding * numTabs)

        local extraSpace = math_max(0, barWidth - totalMinWidth)
        local extraPerTab = extraSpace / numTabs

        local xOffset = 0
        for _, btn in ipairs(tabButtons) do
            local tabWidth = btn.textWidth + minPadding + extraPerTab

            btn:ClearAllPoints()
            btn:SetPoint("TOP", tabBar, "TOP", 0, 0)
            btn:SetPoint("BOTTOM", tabBar, "BOTTOM", 0, 0)
            btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
            btn:SetWidth(tabWidth)

            xOffset = xOffset + tabWidth
        end
    end

    tabBar:SetScript("OnSizeChanged", function(self, width)
        LayoutTabs(width)
    end)

    C_Timer.After(0, function()
        LayoutTabs(tabBar:GetWidth())
        UpdateTabVisuals()
    end)

    local api = {
        panel = panel,
        tabBar = tabBar,
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        scrollbar = scrollbar,
    }

    function api:GetCurrentTab()
        return currentTab
    end

    function api:SetCurrentTab(tabId)
        if currentTab ~= tabId then
            currentTab = tabId
            UpdateTabVisuals()
            if onTabChanged then
                onTabChanged(currentTab)
            end
        end
    end

    function api:ClearContent()
        contentArea.ClearContent()
    end

    function api:RegisterCard(card)
        contentArea.RegisterCard(card)
    end

    function api:SetContentHeight(height)
        contentArea.SetContentHeight(height)
    end

    function api:UpdateScrollBarVisibility()
        contentArea.UpdateScrollBarVisibility()
    end

    function api:ApplyThemeColors()
        tabBarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
        tabBarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        for _, btn in ipairs(tabButtons) do
            btn.selectedOverlay:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.08)
            btn.underline:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end

        UpdateTabVisuals()
        if scrollbar.ApplyThemeColors then scrollbar:ApplyThemeColors() end
    end

    return api
end
