-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ContentAreas.lua                                    ║
-- ║  Purpose: Reusable scrollable content area factory and   ║
-- ║  mini-sidebar (left list + right content) factory.       ║
-- ║  Used by sub-tab panels and any list-detail UI.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
KE.GUI = KE.GUI or {}

local CreateFrame = CreateFrame
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local C_Timer = C_Timer

---Private helper to create shared scroll infrastructure.
local function CreateScrollableArea(parent, options)
    local Theme = KE.Theme
    options = options or {}
    local scrollbarWidth = options.scrollbarWidth or Theme.scrollbarWidth or 16
    local baseWidth = options.baseWidth
    local noScrollbarOffset = options.noScrollbarOffset or 0
    local scrollbarOptions = options.scrollbarOptions or {
        width = 16,
        thumbHeight = 40,
        padding = { top = -1, bottom = -1, right = 0 },
        scrollStep = 40,
    }

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    if options.anchor then
        scrollFrame:SetPoint("TOPLEFT", options.anchor, "BOTTOMLEFT", 0, options.anchorOffsetY or -1)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    else
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
    scrollFrame:SetClipsChildren(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollbar = KE.GUI.CreateScrollbar(scrollFrame, scrollbarOptions)

    local scrollbarVisible = false
    local activeCards = {}

    local function UpdateScrollChildWidth()
        if not baseWidth then
            baseWidth = parent:GetWidth()
        end
        if scrollbarVisible then
            scrollChild:SetWidth(baseWidth - scrollbarWidth)
        else
            scrollChild:SetWidth(baseWidth - noScrollbarOffset)
        end
    end

    local function UpdateScrollBarVisibility()
        local contentHeight = scrollChild:GetHeight()
        local frameHeight = scrollFrame:GetHeight()
        scrollbarVisible = scrollbar:UpdateVisibility(contentHeight, frameHeight)
        UpdateScrollChildWidth()
    end

    local function UpdateCardWidths()
        local newWidth = scrollChild:GetWidth()
        for _, card in ipairs(activeCards) do
            if card and card.SetWidth then
                card:SetWidth(newWidth)
            end
        end
    end

    UpdateScrollChildWidth()

    scrollChild:HookScript("OnSizeChanged", function()
        UpdateScrollBarVisibility()
        UpdateCardWidths()
    end)
    scrollFrame:HookScript("OnSizeChanged", UpdateScrollBarVisibility)
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, UpdateScrollBarVisibility)
    end)

    local function ClearContent()
        wipe(activeCards)
        for _, child in ipairs({ scrollChild:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
        for _, region in ipairs({ scrollChild:GetRegions() }) do
            if region:IsObjectType("FontString") or region:IsObjectType("Texture") then
                region:Hide()
            end
        end
        scrollChild:SetHeight(1)
    end

    local function RegisterCard(card)
        activeCards[#activeCards + 1] = card
    end

    local function SetContentHeight(height)
        scrollChild:SetHeight(height)
    end

    return {
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        scrollbar = scrollbar,
        activeCards = activeCards,
        UpdateScrollBarVisibility = UpdateScrollBarVisibility,
        UpdateCardWidths = UpdateCardWidths,
        ClearContent = ClearContent,
        RegisterCard = RegisterCard,
        SetContentHeight = SetContentHeight,
    }
end

---Create a basic scrollable content area (backdrop + scroll frame + custom scrollbar).
function KE.GUI.CreateBasicContentArea(container, options)
    local Theme = KE.Theme
    options = options or {}

    local frame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    frame:SetAllPoints(container)

    if options.showBackground ~= false then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
        })
        frame:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
    end

    local scrollArea = CreateScrollableArea(frame, {
        baseWidth = options.contentWidth or container:GetWidth(),
        scrollbarWidth = options.scrollbarWidth or Theme.scrollbarWidth or 16,
        noScrollbarOffset = options.noScrollbarOffset or 0,
        scrollbarOptions = options.scrollbarOptions or {
            width = 16,
            thumbHeight = 40,
            padding = { top = -1, bottom = -1, right = 0 },
            scrollStep = 40,
        },
    })

    local function ApplyThemeColors()
        if options.showBackground ~= false then
            frame:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], Theme.bgDark[4])
        end
        scrollArea.scrollbar:ApplyThemeColors()
    end

    return {
        frame = frame,
        scrollFrame = scrollArea.scrollFrame,
        scrollChild = scrollArea.scrollChild,
        scrollbar = scrollArea.scrollbar,
        activeCards = scrollArea.activeCards,
        ClearContent = scrollArea.ClearContent,
        RegisterCard = scrollArea.RegisterCard,
        SetContentHeight = scrollArea.SetContentHeight,
        UpdateScrollBarVisibility = scrollArea.UpdateScrollBarVisibility,
        UpdateCardWidths = scrollArea.UpdateCardWidths,
        ApplyThemeColors = ApplyThemeColors,
    }
end

---Create a mini sidebar layout: left list + right content area.
---Self-contained component with built-in pooled item rendering.
function KE.GUI.CreateMiniSidebar(container, options)
    local Theme = KE.Theme
    options = options or {}
    local sidebarWidth = options.sidebarWidth or 192
    local listPadding = options.listPadding or 4
    local itemHeight = options.itemHeight or 26
    local itemSpacing = options.itemSpacing or 1

    local getItems = options.getItems
    local renderItem = options.renderItem
    local onItemSelected = options.onItemSelected
    local getItemKey = options.getItemKey or function(item) return item.key or item.id or item.name end
    local customListRendering = options.customListRendering or false

    local panel = CreateFrame("Frame", nil, container)
    panel:SetAllPoints()

    local sidebar = CreateFrame("Frame", nil, panel)
    sidebar:SetWidth(sidebarWidth)
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)

    local sidebarBorder = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    local buttonAreaConfig = options.buttonArea or {}
    local buttonAreaHeight = 0
    local actionButtons = {}

    local buttonArea = CreateFrame("Frame", nil, sidebar)
    buttonArea:SetPoint("TOPLEFT", sidebar, "TOPLEFT", listPadding, -listPadding)
    buttonArea:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -listPadding, -listPadding)

    local hasButtons = (buttonAreaConfig.buttons and #buttonAreaConfig.buttons > 0) or
        (buttonAreaConfig.rows and #buttonAreaConfig.rows > 0)

    -- Hoisted so ApplyThemeColors can re-tint after a theme switch (the
    -- accent line under the action button area). nil when hasButtons=false.
    local actionAccentBorder
    if hasButtons then
        local btnHeight = buttonAreaConfig.buttonHeight or 22
        local layout = buttonAreaConfig.layout or "vertical"
        local spacing = buttonAreaConfig.spacing or listPadding
        local rowSpacing = buttonAreaConfig.rowSpacing or 2
        local bgColor = Theme.bgLight

        local borderBottom = buttonArea:CreateTexture(nil, "ARTWORK")
        actionAccentBorder = borderBottom
        borderBottom:SetHeight(1)
        borderBottom:SetPoint("BOTTOMLEFT", buttonArea, "BOTTOMLEFT", 0, -Theme.paddingSmall)
        borderBottom:SetPoint("BOTTOMRIGHT", buttonArea, "BOTTOMRIGHT", 0, 0)
        borderBottom:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)

        if layout == "horizontal" then
            local rows = buttonAreaConfig.rows or { buttonAreaConfig.buttons }
            local numRows = #rows
            buttonAreaHeight = (btnHeight * numRows) + (rowSpacing * (numRows - 1)) + listPadding
            local availableWidth = sidebarWidth - listPadding * 2
            local buttonIndex = 1

            for rowIndex, rowButtons in ipairs(rows) do
                local numButtons = #rowButtons
                local totalSpacing = spacing * (numButtons - 1)
                local btnWidth = (availableWidth - totalSpacing) / numButtons
                local rowYOffset = (rowIndex - 1) * (btnHeight + rowSpacing)

                for colIndex, btnConfig in ipairs(rowButtons) do
                    local btn = CreateFrame("Button", nil, buttonArea, "BackdropTemplate")
                    btn:SetSize(btnWidth, btnHeight)
                    btn._bgColor = bgColor

                    local xOffset = (colIndex - 1) * (btnWidth + spacing)
                    btn:SetPoint("TOPLEFT", buttonArea, "TOPLEFT", xOffset, -rowYOffset)

                    btn:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = 1,
                    })
                    btn:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], 1)
                    btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

                    local hoverAnimGroup = btn:CreateAnimationGroup()
                    hoverAnimGroup:CreateAnimation("Animation"):SetDuration(Theme.animDuration or 0.15)

                    local borderColorFrom = {}
                    local borderColorTo = {}

                    hoverAnimGroup:SetScript("OnUpdate", function(anim)
                        local progress = anim:GetProgress() or 0
                        local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
                        local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
                        local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
                        btn:SetBackdropBorderColor(r, g, b, 1)
                    end)

                    hoverAnimGroup:SetScript("OnFinished", function()
                        btn:SetBackdropBorderColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, 1)
                    end)

                    local function AnimateBorderColor(toAccent)
                        hoverAnimGroup:Stop()
                        local currentR, currentG, currentB = btn:GetBackdropBorderColor()
                        borderColorFrom.r, borderColorFrom.g, borderColorFrom.b = currentR, currentG, currentB
                        if toAccent then
                            borderColorTo.r, borderColorTo.g, borderColorTo.b = Theme.accent[1], Theme.accent[2], Theme.accent[3]
                        else
                            borderColorTo.r, borderColorTo.g, borderColorTo.b = Theme.border[1], Theme.border[2], Theme.border[3]
                        end
                        hoverAnimGroup:Play()
                    end

                    if btnConfig.icon then
                        local iconSize = btnHeight - 6
                        local icon = btn:CreateTexture(nil, "ARTWORK")
                        icon:SetSize(iconSize, iconSize)
                        icon:SetPoint("CENTER")
                        icon:SetTexture(btnConfig.icon)
                        icon:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                        if btnConfig.iconRotation then
                            icon:SetRotation(math.rad(btnConfig.iconRotation))
                        end
                        btn._icon = icon
                    else
                        local label = btn:CreateFontString(nil, "OVERLAY")
                        label:SetPoint("CENTER")
                        KE:ApplyThemeFont(label, "small")
                        label:SetText(btnConfig.text or "")
                        label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                        btn._label = label
                    end

                    btn:SetScript("OnEnter", function(self)
                        AnimateBorderColor(true)
                        if btnConfig.tooltip then
                            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
                            GameTooltip:SetText(btnConfig.tooltip, Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                            GameTooltip:Show()
                        end
                    end)

                    btn:SetScript("OnLeave", function(self)
                        AnimateBorderColor(false)
                        self:SetBackdropColor(self._bgColor[1], self._bgColor[2], self._bgColor[3], 1)
                        GameTooltip:Hide()
                    end)

                    btn:SetScript("OnMouseDown", function(self)
                        self:SetBackdropColor(Theme.selectedBg[1], Theme.selectedBg[2], Theme.selectedBg[3], Theme.selectedBg[4] or 1)
                    end)

                    btn:SetScript("OnMouseUp", function(self)
                        self:SetBackdropColor(self._bgColor[1], self._bgColor[2], self._bgColor[3], 1)
                    end)

                    btn:SetScript("OnClick", btnConfig.onClick)
                    actionButtons[buttonIndex] = btn
                    buttonIndex = buttonIndex + 1
                end
            end
        else
            buttonAreaHeight = btnHeight + listPadding
            local GUIFrame = KE.GUIFrame
            for i, btnConfig in ipairs(buttonAreaConfig.buttons) do
                local btn = GUIFrame:CreateButton(buttonArea, btnConfig.text, {
                    height = btnHeight,
                    bgColor = Theme.bgLight,
                    callback = btnConfig.onClick,
                })
                btn:SetPoint("TOPLEFT", buttonArea, "TOPLEFT", 0, 0)
                btn:SetPoint("TOPRIGHT", buttonArea, "TOPRIGHT", 0, 0)
                actionButtons[i] = btn
            end
        end
    end
    buttonArea:SetHeight(buttonAreaHeight)

    local listFrame = CreateFrame("ScrollFrame", nil, sidebar)
    if buttonAreaHeight > 0 then
        listFrame:SetPoint("TOPLEFT", buttonArea, "BOTTOMLEFT", 0, -listPadding - Theme.paddingMedium)
    else
        listFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", listPadding, -listPadding)
    end
    listFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -listPadding, listPadding)
    listFrame:SetClipsChildren(true)

    local listChild = CreateFrame("Frame", nil, listFrame)
    listChild:SetWidth(sidebarWidth - listPadding * 2)
    listChild:SetHeight(1)
    listFrame:SetScrollChild(listChild)

    local listScrollbar = KE.GUI.CreateScrollbar(listFrame, {
        width = 8,
        thumbHeight = 30,
        padding = { top = 0, bottom = 0, right = -listPadding + 2 },
        scrollStep = 30,
    })

    local listScrollbarVisible = false
    local function UpdateListScrollbar()
        local contentHeight = listChild:GetHeight()
        local frameHeight = listFrame:GetHeight()
        listScrollbarVisible = listScrollbar:UpdateVisibility(contentHeight, frameHeight)
        if listScrollbarVisible then
            listChild:SetWidth(sidebarWidth - listPadding * 2 - 10)
        else
            listChild:SetWidth(sidebarWidth - listPadding * 2)
        end
    end

    listChild:HookScript("OnSizeChanged", UpdateListScrollbar)
    listFrame:HookScript("OnSizeChanged", UpdateListScrollbar)

    local buttonPool = {}
    local activeButtons = {}
    local selectedKey = nil

    local function SetListHeight(height)
        listChild:SetHeight(height)
    end

    local function GetPooledButton()
        if customListRendering then return nil end
        for _, btn in ipairs(buttonPool) do
            if not btn._inUse then
                btn._inUse = true
                btn:SetParent(listChild)
                btn:Show()
                return btn
            end
        end

        local btn = CreateFrame("Button", nil, listChild)
        btn:SetHeight(itemHeight)

        local hover = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.05)
        hover:Hide()
        btn._hover = hover

        local selected = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        selected:SetAllPoints()
        selected:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.15)
        selected:Hide()
        btn._selected = selected

        local accentBar = btn:CreateTexture(nil, "OVERLAY")
        accentBar:SetWidth(2)
        accentBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        accentBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        accentBar:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        accentBar:Hide()
        btn._accentBar = accentBar

        local iconSize = itemHeight - 6
        local iconBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        iconBorder:SetSize(iconSize + 2, iconSize + 2)
        iconBorder:SetPoint("LEFT", btn, "LEFT", 5, 0)
        iconBorder:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        iconBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        btn._iconBorder = iconBorder

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        btn._icon = icon

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        KE:ApplyThemeFont(label, "small")
        btn._label = label

        btn:SetScript("OnEnter", function(self) self._hover:Show() end)
        btn:SetScript("OnLeave", function(self) self._hover:Hide() end)

        btn._inUse = true
        buttonPool[#buttonPool + 1] = btn
        return btn
    end

    local function ReleaseAllButtons()
        for _, btn in ipairs(buttonPool) do
            btn._inUse = false
            btn:Hide()
            btn:SetScript("OnClick", nil)
        end
        wipe(activeButtons)
    end

    local function UpdateSelectionVisuals()
        for _, btn in ipairs(activeButtons) do
            local isSelected = btn._itemKey == selectedKey
            if isSelected then
                btn._selected:Show()
                btn._accentBar:Show()
            else
                btn._selected:Hide()
                btn._accentBar:Hide()
            end

            if renderItem and btn._itemData then
                renderItem(btn, btn._itemData, isSelected)
            else
                if isSelected then
                    btn._label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    btn._label:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                end
            end
        end
    end

    local function RefreshList()
        if customListRendering then
            C_Timer.After(0, UpdateListScrollbar)
            return
        end

        ReleaseAllButtons()

        if not getItems then return end
        local items = getItems()
        if not items then return end

        for i, item in ipairs(items) do
            local btn = GetPooledButton()
            local key = getItemKey(item)
            btn._itemKey = key
            btn._itemData = item

            btn:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * (itemHeight + itemSpacing))
            btn:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(i - 1) * (itemHeight + itemSpacing))

            if renderItem then
                renderItem(btn, item, key == selectedKey)
            else
                btn._label:SetText(item.text or item.name or tostring(key))
                btn._icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            end

            btn:SetScript("OnClick", function()
                selectedKey = key
                UpdateSelectionVisuals()
                if onItemSelected then
                    onItemSelected(item, key)
                end
            end)

            activeButtons[#activeButtons + 1] = btn
        end

        listChild:SetHeight(#items * (itemHeight + itemSpacing))
        UpdateSelectionVisuals()
        C_Timer.After(0, UpdateListScrollbar)
    end

    local function SelectItem(key)
        selectedKey = key
        UpdateSelectionVisuals()
    end

    local function GetSelectedKey()
        return selectedKey
    end

    local function GetSelectedItem()
        for _, btn in ipairs(activeButtons) do
            if btn._itemKey == selectedKey then
                return btn._itemData
            end
        end
        return nil
    end

    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    contentFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local contentArea
    local contentType = options.contentType or "basic"
    local contentWidth = options.contentWidth or (Theme.contentWidth - sidebarWidth - 1)

    if contentType == "tabbed" and options.tabs then
        contentArea = KE.GUI.CreateSubTabPanel(contentFrame, options.tabs, {
            contentWidth = contentWidth,
            tabBarHeight = options.tabBarHeight,
            defaultTab = options.defaultTab,
            onTabChanged = options.onTabChanged,
        })
    else
        contentArea = KE.GUI.CreateBasicContentArea(contentFrame, {
            contentWidth = contentWidth,
            showBackground = false,
            scrollbarOptions = {
                width = 16,
                thumbHeight = 40,
                padding = { top = 0, bottom = 0, right = 0 },
                scrollStep = 40,
                anchorToScrollFrame = true,
            },
        })
    end

    local function ApplyThemeColors()
        sidebarBg:SetColorTexture(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
        sidebarBorder:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        listScrollbar:ApplyThemeColors()

        for _, btn in ipairs(buttonPool) do
            btn._selected:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.15)
            btn._accentBar:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            btn._iconBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        end
        UpdateSelectionVisuals()

        -- Refresh the action-button area too. KE:RefreshTheme replaces the
        -- color tables (Theme.bgLight, Theme.accent, Theme.border) with new
        -- ones via CopyColor, so any captured table reference becomes stale.
        -- Re-bind btn._bgColor to the live Theme.bgLight so OnLeave / OnMouseUp
        -- handlers see the new palette, and re-apply the visible colors set
        -- at construction time.
        if actionAccentBorder then
            actionAccentBorder:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        end
        for _, btn in ipairs(actionButtons) do
            btn._bgColor = Theme.bgLight
            btn:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
            btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
            if btn._icon then
                btn._icon:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            end
            if btn._label then
                btn._label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            end
        end

        if contentArea.ApplyThemeColors then
            contentArea.ApplyThemeColors()
        end
    end

    return {
        panel = panel,
        sidebar = sidebar,
        buttonArea = buttonArea,
        actionButtons = actionButtons,
        contentArea = contentArea,

        RefreshList = RefreshList,
        SelectItem = SelectItem,
        GetSelectedKey = GetSelectedKey,
        GetSelectedItem = GetSelectedItem,

        listChild = listChild,
        SetListHeight = SetListHeight,
        UpdateListScrollbar = UpdateListScrollbar,

        ApplyThemeColors = ApplyThemeColors,
    }
end
