-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KEDropdown.lua                                      ║
-- ║  Purpose: Dropdown selector widget for the settings      ║
-- ║  panel.                                                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local tostring = tostring
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local math_max, math_min = math.max, math.min
local UIParent = UIParent
local type = type
local table_insert, table_sort, table_remove = table.insert, table.sort, table.remove
local wipe = wipe
local IsMouseButtonDown = IsMouseButtonDown
local ipairs = ipairs
local pairs = pairs

---------------------------------------------------------------------------------
-- Widget Creation
---------------------------------------------------------------------------------

-- Configuration constants
local ROW_HEIGHT = 34
local DROPDOWN_HEIGHT = 24
local ITEM_HEIGHT = 24
local MAX_DROPDOWN_HEIGHT = 400
local ANIMATION_DURATION = 0.12
local ARROW_SIZE = 16
local SEARCH_BOX_HEIGHT = 24
local SEARCH_PADDING = 4
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local ENABLE_ANIMATIONS = true

-- Cached backdrop tables
local DROPDOWN_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
local SCROLLBAR_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
local BORDER_ONLY_BACKDROP = {
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local globalMouseChecker = CreateFrame("Frame", nil, UIParent)
globalMouseChecker:Hide()
globalMouseChecker.activeDropdown = nil
globalMouseChecker.wasMouseDown = false

globalMouseChecker:SetScript("OnUpdate", function(self)
    local dropdown = self.activeDropdown
    if not dropdown then
        self:Hide()
        return
    end

    local isDown = IsMouseButtonDown("LeftButton")
    if self.wasMouseDown and not isDown then
        local dropdownList = dropdown._dropdownList
        local dropdownButton = dropdown._dropdownButton
        if dropdownList and dropdownButton then
            if not dropdownList:IsMouseOver() and not dropdownButton:IsMouseOver() then
                if dropdown._closeDropdown then
                    dropdown._closeDropdown()
                end
            end
        end
    end
    self.wasMouseDown = isDown
end)

local itemButtonPool = {}

local function AcquireItemButton(parent)
    local btn = table_remove(itemButtonPool)
    if btn then
        btn:SetParent(parent)
        btn:Show()
    else
        btn = CreateFrame("Button", nil, parent)
        btn:SetHeight(ITEM_HEIGHT)

        local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:Hide()
        btn._hoverBg = hoverBg

        local btnText = btn:CreateFontString(nil, "OVERLAY")
        btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btnText:SetJustifyH("LEFT")
        btn._text = btnText
    end

    -- Every dropdown shares these buttons, and the theme can change while one
    -- waits in the pool.
    btn._hoverBg:SetColorTexture(
        Theme.accentHover[1],
        Theme.accentHover[2],
        Theme.accentHover[3],
        Theme.accentHover[4] or 0.25
    )
    KE:ApplyThemeFont(btn._text, "normal")

    return btn
end

local function ReleaseItemButton(btn)
    btn:Hide()
    btn:SetParent(nil)
    btn:SetScript("OnClick", nil)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn._hoverBg:Hide()
    btn._itemValue = nil
    btn._itemText = nil
    btn._updateColor = nil
    table_insert(itemButtonPool, btn)
end

-- An options list comes in three shapes: an ordered list of { value or key,
-- text } entries, a plain list of strings, or a key -> text map. For the first
-- shape the options a dropdown is created with read value first, while
-- UpdateOptions reads key first.
local function NormalizeOptions(options, valueFirst)
    local normalized, ordered = {}, nil
    if type(options) == "table" then
        local first = options[1]
        if first and type(first) == "table" and (first.value or first.key) then
            ordered = {}
            for _, opt in ipairs(options) do
                local optKey
                if valueFirst then
                    optKey = opt.value or opt.key
                else
                    optKey = opt.key or opt.value
                end
                normalized[optKey] = opt.text
                table_insert(ordered, optKey)
            end
        elseif first ~= nil and type(first) == "string" then
            for _, v in ipairs(options) do
                normalized[v] = v
            end
        else
            for k, v in pairs(options) do
                normalized[k] = v
            end
        end
    end
    return normalized, ordered
end

-- Builds one dropdown. The search box exists only on searchable dropdowns, so
-- those have their own pool. Label, options, value and bindings are applied
-- by ConfigureDropdown.
local function ConstructDropdown(parent, searchable)
    local row = CreateFrame("Frame", nil, parent)

    -- Label
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    row.label = label

    -- Main dropdown button
    local dropdownButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    dropdownButton:SetHeight(DROPDOWN_HEIGHT)
    dropdownButton:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    dropdownButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -14)
    dropdownButton:SetBackdrop(DROPDOWN_BACKDROP)

    -- Selected text
    local selectedText = dropdownButton:CreateFontString(nil, "OVERLAY")
    selectedText:SetPoint("LEFT", dropdownButton, "LEFT", Theme.paddingSmall, 0)
    selectedText:SetPoint("RIGHT", dropdownButton, "RIGHT", -24, 0)
    selectedText:SetJustifyH("LEFT")
    dropdownButton.selectedText = selectedText

    -- Arrow icon
    local arrow = dropdownButton:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("RIGHT", dropdownButton, "RIGHT", -Theme.paddingSmall, 0)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetTexelSnappingBias(0)
    arrow:SetSnapToPixelGrid(false)
    arrow:SetRotation(-math.pi / 2)

    -- State variables
    local normalizedOptions = {}
    local orderedKeys
    local isOpen = false
    local currentValue
    local itemButtons = {}
    local itemsCreated = false
    local startHeight = 0
    local targetHeight = 0
    local scrollHold = false
    local searchText = ""

    -- Dropdown list
    local dropdownList = CreateFrame("Frame", nil, row, "BackdropTemplate")
    dropdownList:SetHeight(1)
    dropdownList:SetBackdrop(DROPDOWN_BACKDROP)
    dropdownList:SetFrameStrata("TOOLTIP")
    dropdownList:SetClipsChildren(true)
    dropdownList:Hide()

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, dropdownList)
    scrollFrame:SetPoint("TOPLEFT", dropdownList, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", 0, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)

    local searchContainer, searchBox, searchEmptyLabel
    if searchable then
        searchContainer = CreateFrame("Frame", nil, dropdownList, "BackdropTemplate")
        searchContainer:SetHeight(SEARCH_BOX_HEIGHT)
        searchContainer:SetPoint("TOPLEFT", dropdownList, "TOPLEFT", 0, 0)
        searchContainer:SetPoint("TOPRIGHT", dropdownList, "TOPRIGHT", 0, 0)
        searchContainer:SetBackdrop(DROPDOWN_BACKDROP)

        searchBox = CreateFrame("EditBox", nil, searchContainer)
        searchBox:SetAutoFocus(false)
        searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 8, 0)
        searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -8, 0)
        KE:ApplyThemeFont(searchBox, "normal")

        searchEmptyLabel = dropdownList:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(searchEmptyLabel, "normal")
        searchEmptyLabel:SetPoint("TOP", searchContainer, "BOTTOM", 0, -(SEARCH_PADDING + 6))
        searchEmptyLabel:SetText("No matches found")
        searchEmptyLabel:Hide()

        scrollFrame:SetPoint("TOPLEFT", dropdownList, "TOPLEFT", 0, -(SEARCH_BOX_HEIGHT + SEARCH_PADDING))
    end

    -- Scrollbar components
    local scrollbar
    local thumb
    local thumbBorder

    local function EnsureScrollbar()
        if scrollbar then return end

        scrollbar = CreateFrame("Slider", nil, dropdownList, "BackdropTemplate")
        scrollbar:SetPoint("TOPRIGHT", dropdownList, "TOPRIGHT", 0,
            searchable and -(SEARCH_BOX_HEIGHT + SEARCH_PADDING) or 0)
        scrollbar:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", 0, 0)
        scrollbar:SetWidth(12)
        scrollbar:SetBackdrop(SCROLLBAR_BACKDROP)
        scrollbar:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        scrollbar:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        scrollbar:SetOrientation("VERTICAL")
        local pxlPerfStep = KE:PixelBestSize()
        scrollbar:SetValueStep(pxlPerfStep)
        scrollbar:SetMinMaxValues(0, 100)
        scrollbar:SetValue(0)
        scrollbar:Hide()

        scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        scrollbar:SetScript("OnValueChanged", function(_, value)
            scrollFrame:SetVerticalScroll(value)
        end)

        scrollbar:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                scrollHold = true
            end
        end)
        scrollbar:SetScript("OnMouseUp", function(_, button)
            -- A release to the pool ends the hold itself. Neither this clear
            -- nor a mouse-up while parked may reach the dropdown's next use.
            if button == "LeftButton" and row._keState ~= "free" then
                local gen = row._keGen
                C_Timer.After(0.1, function()
                    if row._keGen == gen then scrollHold = false end
                end)
            end
        end)

        thumb = scrollbar:GetThumbTexture()
        thumb:SetSize(12, 30)
        thumb:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)

        thumbBorder = CreateFrame("Frame", nil, scrollbar, "BackdropTemplate")
        thumbBorder:SetPoint("TOPLEFT", thumb, 0, 0)
        thumbBorder:SetPoint("BOTTOMRIGHT", thumb, 0, 0)
        thumbBorder:SetBackdrop(BORDER_ONLY_BACKDROP)
        thumbBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

        thumb:HookScript("OnShow", function() thumbBorder:Show() end)
        thumb:HookScript("OnHide", function() thumbBorder:Hide() end)

        -- The list's own part, made on first need, not something a page added.
        GUIFrame:PoolGrow(row, dropdownList, 1, 0)
    end

    -- Animation groups
    local animGroup, arrowAnimGroup, arrowRotation

    if ENABLE_ANIMATIONS then
        animGroup = dropdownList:CreateAnimationGroup()
        local heightAnim = animGroup:CreateAnimation("Animation")
        heightAnim:SetDuration(ANIMATION_DURATION)

        arrowAnimGroup = arrow:CreateAnimationGroup()
        arrowRotation = arrowAnimGroup:CreateAnimation("Rotation")
        arrowRotation:SetDuration(ANIMATION_DURATION)
        arrowRotation:SetOrigin("CENTER", 0, 0)
        arrowRotation:SetSmoothing("IN_OUT")

        arrowAnimGroup:SetScript("OnFinished", function()
            arrow:SetRotation(isOpen and 0 or -math.pi / 2)
        end)
    end

    -- Border hover animation
    local hoverAnimGroup, hoverAnim
    local borderColorFrom = { r = Theme.controlBorder[1], g = Theme.controlBorder[2], b = Theme.controlBorder[3] }
    local borderColorTo = { r = Theme.controlBorder[1], g = Theme.controlBorder[2], b = Theme.controlBorder[3] }

    if ENABLE_ANIMATIONS then
        hoverAnimGroup = dropdownButton:CreateAnimationGroup()
        hoverAnim = hoverAnimGroup:CreateAnimation("Animation")
        hoverAnim:SetDuration(0.15)

        hoverAnimGroup:SetScript("OnUpdate", function(self)
            local progress = self:GetProgress() or 0
            local r = borderColorFrom.r + (borderColorTo.r - borderColorFrom.r) * progress
            local g = borderColorFrom.g + (borderColorTo.g - borderColorFrom.g) * progress
            local b = borderColorFrom.b + (borderColorTo.b - borderColorFrom.b) * progress
            dropdownButton:SetBackdropBorderColor(r, g, b, 1)
        end)

        hoverAnimGroup:SetScript("OnFinished", function()
            dropdownButton:SetBackdropBorderColor(borderColorTo.r, borderColorTo.g, borderColorTo.b, 1)
        end)
    end

    local function SetBorderHover(hovered)
        if ENABLE_ANIMATIONS and hoverAnimGroup then
            hoverAnimGroup:Stop()

            local currentR, currentG, currentB = dropdownButton:GetBackdropBorderColor()
            borderColorFrom.r = currentR
            borderColorFrom.g = currentG
            borderColorFrom.b = currentB

            if hovered then
                borderColorTo.r = Theme.accent[1]
                borderColorTo.g = Theme.accent[2]
                borderColorTo.b = Theme.accent[3]
            else
                borderColorTo.r = Theme.controlBorder[1]
                borderColorTo.g = Theme.controlBorder[2]
                borderColorTo.b = Theme.controlBorder[3]
            end

            hoverAnimGroup:Play()
        else
            -- Instant fallback
            if hovered then
                dropdownButton:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            else
                dropdownButton:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Dropdown Logic
    ---------------------------------------------------------------------------------

    -- Close dropdown function
    local function CloseDropdown(instant)
        if scrollHold and not instant then return end
        -- `instant` forces cleanup even when isOpen is already false. An animated close
        -- sets isOpen=false but defers Hide()+reparent to the 0.12s OnFinished, so a
        -- button Hide() in that window (e.g. a callback that rebuilds the page) must still
        -- force the overlay-parented list down -- otherwise it lingers as a ghost copy at
        -- the bottom of the panel.
        if not isOpen and not instant then return end

        isOpen = false

        if searchable then
            searchText = ""
            if searchBox then
                searchBox:ClearFocus()
                searchBox:SetText("")
            end
            if searchEmptyLabel then searchEmptyLabel:Hide() end
        end

        -- Force instant if animations disabled
        if not ENABLE_ANIMATIONS then
            instant = true
        end

        if instant then
            dropdownList:SetHeight(1)
            dropdownList:Hide()

            if dropdownList._logicalParent then
                dropdownList:SetParent(dropdownList._logicalParent)
                dropdownList._logicalParent = nil
            end

            arrow:SetRotation(-math.pi / 2)
            if animGroup then animGroup:Stop() end
            if arrowAnimGroup then arrowAnimGroup:Stop() end
        else
            startHeight = dropdownList:GetHeight()
            targetHeight = 1
            if arrowAnimGroup then
                arrowAnimGroup:Stop()
                arrowRotation:SetRadians(-math.pi / 2)
                arrowAnimGroup:Play()
            end
            if animGroup then
                animGroup:Stop()
                animGroup:Play()
            end
        end

        -- Unregister from global mouse checker
        if globalMouseChecker.activeDropdown == row then
            globalMouseChecker.activeDropdown = nil
            globalMouseChecker:Hide()
        end

        if GUIFrame.activeDropdown == dropdownButton then
            GUIFrame.activeDropdown = nil
        end
    end

    -- Update scroll state
    local function UpdateScroll()
        local contentHeight = scrollChild:GetHeight()
        local scrollFrameHeight = scrollFrame:GetHeight()
        local needsScrollbar = contentHeight > scrollFrameHeight and scrollFrameHeight > 0

        if needsScrollbar then
            EnsureScrollbar()
            if scrollbar then
                scrollbar:Show()
                scrollbar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
                scrollbar:SetValue(0)
            end
            scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", -11, 0)
        else
            if scrollbar then
                scrollbar:Hide()
                scrollbar:SetMinMaxValues(0, 0)
            end
            scrollFrame:SetVerticalScroll(0)
            scrollFrame:SetPoint("BOTTOMRIGHT", dropdownList, "BOTTOMRIGHT", 0, 0)
        end

        scrollChild:SetWidth(scrollFrame:GetWidth())

        -- Position buttons using stored index
        for _, btn in ipairs(itemButtons) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(btn._index - 1) * ITEM_HEIGHT)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        end
    end

    -- Animation scripts
    if ENABLE_ANIMATIONS and animGroup then
        animGroup:SetScript("OnUpdate", function(self)
            local progress = self:GetProgress() or 0
            local smoothProgress = progress * progress * (3 - 2 * progress)
            local newHeight = startHeight + (targetHeight - startHeight) * smoothProgress
            dropdownList:SetHeight(newHeight)

            if isOpen and newHeight < targetHeight then
                dropdownList:SetClipsChildren(false)
            end
        end)

        animGroup:SetScript("OnFinished", function()
            dropdownList:SetHeight(targetHeight)

            if not isOpen then
                dropdownList:Hide()

                if dropdownList._logicalParent then
                    dropdownList:SetParent(dropdownList._logicalParent)
                    dropdownList._logicalParent = nil
                end
            else
                dropdownList:SetClipsChildren(true)
            end
        end)
    end

    -- Create item buttons
    local function CreateItemButtons()
        -- Release existing buttons back to pool
        for _, btn in ipairs(itemButtons) do
            ReleaseItemButton(btn)
        end
        wipe(itemButtons)

        local sortedKeys
        if orderedKeys then
            sortedKeys = orderedKeys
        else
            sortedKeys = {}
            for k in pairs(normalizedOptions) do
                table_insert(sortedKeys, k)
            end
            table_sort(sortedKeys, function(a, b)
                return tostring(a) < tostring(b)
            end)
        end

        local visibleKeys = sortedKeys
        if searchable and searchText ~= "" then
            visibleKeys = {}
            for _, key in ipairs(sortedKeys) do
                if KE.DropdownSearchMatches(normalizedOptions[key], key, searchText) then
                    table_insert(visibleKeys, key)
                end
            end
        end

        for i, key in ipairs(visibleKeys) do
            local displayText = normalizedOptions[key]

            local btn = AcquireItemButton(scrollChild)
            btn._itemValue = key
            btn._itemText = displayText
            btn._index = i -- Store index directly on button
            btn._text:SetText(displayText or key)

            -- Update color function
            local function UpdateItemColor()
                if currentValue == btn._itemValue then
                    btn._text:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    btn._text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
                end
            end
            btn._updateColor = UpdateItemColor
            UpdateItemColor()

            btn:SetScript("OnClick", function()
                currentValue = btn._itemValue
                selectedText:SetText(btn._itemText or btn._itemValue)

                for _, itemBtn in ipairs(itemButtons) do
                    if itemBtn._updateColor then
                        itemBtn._updateColor()
                    end
                end

                -- Close INSTANTLY (not animated) BEFORE firing the callback. A callback
                -- that rebuilds the page would otherwise orphan the still-animating list
                -- (reparented to KE.GUIOverlay during the 0.12s close) -> a ghost copy of
                -- the menu lingers at the bottom of the panel after a selection.
                CloseDropdown(true)

                if row._callback then
                    row._callback(btn._itemValue)
                end
            end)

            btn:SetScript("OnEnter", function()
                btn._hoverBg:Show()
                btn._text:SetTextColor(Theme.textPrimary[1], Theme.textPrimary[2], Theme.textPrimary[3], 1)
            end)

            btn:SetScript("OnLeave", function()
                btn._hoverBg:Hide()
                UpdateItemColor()
            end)

            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)
            btn:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

            table_insert(itemButtons, btn)
        end

        scrollChild:SetHeight(#visibleKeys * ITEM_HEIGHT)
        itemsCreated = true
    end

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if scrollbar and scrollbar:IsShown() then
            local current = scrollbar:GetValue()
            local minVal, maxVal = scrollbar:GetMinMaxValues()
            local newValue = current - (delta * ITEM_HEIGHT)
            newValue = math_max(minVal, math_min(maxVal, newValue))
            scrollbar:SetValue(newValue)
        end
    end)

    -- Open-menu height: rows plus, when searchable, the docked search bar
    -- (and one row of space for the empty-state label when nothing matches).
    local function ListContentHeight()
        local h = #itemButtons * ITEM_HEIGHT
        if searchable then
            h = h + SEARCH_BOX_HEIGHT + SEARCH_PADDING
            if #itemButtons == 0 then h = h + ITEM_HEIGHT end
        end
        return math_min(h, MAX_DROPDOWN_HEIGHT)
    end

    if searchable then
        searchBox:SetScript("OnTextChanged", function(self, userInput)
            -- Programmatic SetText("") on open/close must not re-filter.
            if not userInput then return end
            searchText = self:GetText() or ""
            CreateItemButtons()
            searchEmptyLabel:SetShown(#itemButtons == 0)
            if isOpen then
                dropdownList:SetHeight(ListContentHeight())
                targetHeight = dropdownList:GetHeight()
                UpdateScroll()
            end
        end)
        -- Enter commits the top match through the row's own click path.
        searchBox:SetScript("OnEnterPressed", function()
            local first = itemButtons[1]
            if first then first:Click() end
        end)
        searchBox:SetScript("OnEscapePressed", function()
            CloseDropdown(true)
        end)
    end

    -- Toggle dropdown
    local function ToggleDropdown()
        if isOpen then
            CloseDropdown()
        else
            if searchable then
                -- Reopen always shows the unfiltered list, focused for typing.
                searchText = ""
                searchBox:SetText("")
                searchEmptyLabel:Hide()
                CreateItemButtons()
                local gen = row._keGen
                C_Timer.After(0, function()
                    if isOpen and row._keGen == gen then
                        searchBox:SetFocus()
                        searchBox:HighlightText(0, 0)
                    end
                end)
            elseif not itemsCreated then
                CreateItemButtons()
            end

            dropdownList._logicalParent = dropdownList:GetParent()
            dropdownList:SetParent(KE.GUIOverlay)
            dropdownList:ClearAllPoints()
            dropdownList:SetPoint("TOPLEFT", dropdownButton, "BOTTOMLEFT", 0, -2)
            dropdownList:SetPoint("TOPRIGHT", dropdownButton, "BOTTOMRIGHT", 0, -2)

            local maxHeight = ListContentHeight()

            startHeight = 1
            targetHeight = maxHeight

            dropdownList:SetHeight(targetHeight)
            scrollChild:SetWidth(scrollFrame:GetWidth())
            UpdateScroll()
            dropdownList:Show()
            dropdownList:SetHeight(startHeight)

            isOpen = true

            -- Close other open dropdown
            if GUIFrame.activeDropdown and GUIFrame.activeDropdown ~= dropdownButton then
                if GUIFrame.activeDropdown.closeDropdown then
                    GUIFrame.activeDropdown.closeDropdown()
                end
            end
            GUIFrame.activeDropdown = dropdownButton

            -- Animate or instant
            if ENABLE_ANIMATIONS and animGroup and arrowAnimGroup then
                arrowAnimGroup:Stop()
                arrowRotation:SetRadians(math.pi / 2)
                arrowAnimGroup:Play()
                animGroup:Play()
            else
                -- Instant open
                arrow:SetRotation(0)
                dropdownList:SetHeight(targetHeight)
            end

            -- Register with global mouse checker
            row._dropdownList = dropdownList
            row._dropdownButton = dropdownButton
            row._closeDropdown = CloseDropdown
            globalMouseChecker.activeDropdown = row
            globalMouseChecker.wasMouseDown = false
            globalMouseChecker:Show()
        end
    end

    -- Button scripts
    dropdownButton:SetScript("OnClick", ToggleDropdown)

    dropdownButton:SetScript("OnEnter", function()
        SetBorderHover(true)
        local tooltip = row._tooltip
        if tooltip then
            GameTooltip:SetOwner(dropdownButton, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    dropdownButton:SetScript("OnLeave", function()
        SetBorderHover(false)
        GameTooltip:Hide()
    end)

    -- Hide handlers
    dropdownList:SetScript("OnHide", function()
        if isOpen then
            isOpen = false
        end
    end)

    dropdownButton:SetScript("OnHide", function()
        CloseDropdown(true)
        if GUIFrame.activeDropdown == dropdownButton then
            GUIFrame.activeDropdown = nil
        end
        -- Pools reuse a hidden button without repainting its hover border.
        if hoverAnimGroup then hoverAnimGroup:Stop() end
        dropdownButton:SetBackdropBorderColor(Theme.controlBorder[1], Theme.controlBorder[2], Theme.controlBorder[3], 1)
    end)

    -- Public API
    function row:SetValue(value, silent)
        currentValue = value
        if normalizedOptions[value] then
            selectedText:SetText(normalizedOptions[value])
        else
            selectedText:SetText(tostring(value))
        end

        -- Only update colors if items exist
        if itemsCreated then
            for _, btn in ipairs(itemButtons) do
                if btn._updateColor then
                    btn._updateColor()
                end
            end
        end

        if row._callback and not silent then
            row._callback(value)
        end
    end

    function row:SetSelected(value, silent)
        return row:SetValue(value, silent)
    end

    function row:GetValue()
        return currentValue
    end

    function row:GetSelected()
        return currentValue
    end

    function row:SetEnabled(enabled)
        if enabled then
            dropdownButton:Enable()
            dropdownButton:SetAlpha(1)
            label:SetAlpha(1)
        else
            dropdownButton:Disable()
            dropdownButton:SetAlpha(0.5)
            label:SetAlpha(0.5)
            if isOpen then
                CloseDropdown(searchable)
            end
        end
    end

    -- Re-apply theme-tied state after KE:RefreshTheme replaces Theme color
    -- tables. Hover/animation handlers read live values via Theme.accent[1]
    -- indexing each call so they self-recover. Item buttons are recreated on
    -- the next open; the list chrome is repainted by ConfigureDropdown.
    function row:ApplyThemeColors()
        local TT = Theme
        label:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        dropdownButton:SetBackdropColor(TT.controlBg[1], TT.controlBg[2], TT.controlBg[3], TT.controlBg[4])
        dropdownButton:SetBackdropBorderColor(TT.controlBorder[1], TT.controlBorder[2], TT.controlBorder[3], 1)
        selectedText:SetTextColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
        arrow:SetVertexColor(TT.accent[1], TT.accent[2], TT.accent[3], 1)
    end

    local function ApplyOptions(newOptions, valueFirst)
        normalizedOptions, orderedKeys = NormalizeOptions(newOptions, valueFirst)

        -- Recreate items if they were already created
        if itemsCreated then
            CreateItemButtons()
            if isOpen then
                if searchable then
                    searchEmptyLabel:SetShown(#itemButtons == 0)
                    dropdownList:SetHeight(ListContentHeight())
                    targetHeight = dropdownList:GetHeight()
                end
                UpdateScroll()
            end
        end
    end
    row._applyOptions = ApplyOptions

    function row:UpdateOptions(newOptions)
        ApplyOptions(newOptions, false)
    end

    function row:SetOptions(newOptions)
        return row:UpdateOptions(newOptions)
    end

    -- The value a dropdown shows before anything is picked.
    row._showSelected = function(value)
        if value and normalizedOptions[value] then
            selectedText:SetText(normalizedOptions[value])
            currentValue = value
        elseif value ~= nil then
            selectedText:SetText(tostring(value))
            currentValue = value
        else
            selectedText:SetText("Select...")
            currentValue = nil
        end
    end

    -- Colors of the parts only seen while the list is open. A fresh dropdown
    -- took them from the theme when it was built; a reused one takes them here.
    row._paintList = function()
        local TT = Theme
        dropdownList:SetBackdropColor(TT.listBg[1], TT.listBg[2], TT.listBg[3], TT.listBg[4])
        dropdownList:SetBackdropBorderColor(TT.listBorder[1], TT.listBorder[2], TT.listBorder[3], 1)
        -- The scrollbar is made on first need and then kept.
        if scrollbar then
            scrollbar:SetBackdropColor(TT.bgDark[1], TT.bgDark[2], TT.bgDark[3], 1)
            scrollbar:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
            thumb:SetColorTexture(TT.accent[1], TT.accent[2], TT.accent[3], 0.8)
            thumbBorder:SetBackdropBorderColor(TT.border[1], TT.border[2], TT.border[3], 1)
        end
        if searchable then
            searchContainer:SetBackdropColor(TT.fieldBg[1], TT.fieldBg[2], TT.fieldBg[3], TT.fieldBg[4])
            searchContainer:SetBackdropBorderColor(TT.fieldBorder[1], TT.fieldBorder[2], TT.fieldBorder[3], 1)
            KE:ApplyThemeFont(searchBox, "normal")
            searchBox:SetTextColor(TT.textPrimary[1], TT.textPrimary[2], TT.textPrimary[3], 1)
            KE:ApplyThemeFont(searchEmptyLabel, "normal")
            searchEmptyLabel:SetTextColor(TT.textSecondary[1], TT.textSecondary[2], TT.textSecondary[3], 1)
        end
    end

    -- Back to rest: list closed, no item buttons, no search, no hover fade.
    row._resetForPool = function()
        CloseDropdown(true)
        for _, btn in ipairs(itemButtons) do
            ReleaseItemButton(btn)
        end
        wipe(itemButtons)
        itemsCreated = false
        scrollHold = false
        if hoverAnimGroup then hoverAnimGroup:Stop() end
    end

    dropdownButton.closeDropdown = CloseDropdown
    row.dropdown = dropdownButton

    -- Pool-friendly callback slot; item OnClick + row:SetValue read late-bound.
    function row:SetCallback(fn)
        self._callback = fn
    end

    row._keOwned = { row, dropdownButton, dropdownList, scrollChild }
    return row
end

local function ConfigureDropdown(row, labelText, config)
    -- Every use: row:AddWidget sizes a widget to its row.
    row:SetHeight(ROW_HEIGHT)
    local label = row.label
    KE:ApplyThemeFont(label, "small")
    label:SetText(labelText or "")
    KE:ApplyThemeFont(row.dropdown.selectedText, "normal")
    row._tooltip = config.tooltip
    row._applyOptions(config.options, true)
    row._showSelected(config.value or config.selected)
    row:SetEnabled(true)
    row:ApplyThemeColors()
    row._paintList()
    row._callback = config.callback
end

local function ResetDropdown(row)
    row._resetForPool()
end

local dropdownPool = GUIFrame:NewWidgetPool("dropdown", function(holder)
    return ConstructDropdown(holder, false)
end, ResetDropdown)

local searchDropdownPool = GUIFrame:NewWidgetPool("dropdown:search", function(holder)
    return ConstructDropdown(holder, true)
end, ResetDropdown)

-- Dropdown Widget — config-table API: { options, value, callback, tooltip,
-- searchable }
-- TODO: `labelWidth` and `isFontPreview` are accepted in the API but not
-- yet wired into the widget body. Config keys pass silently.
function GUIFrame:CreateDropdown(parent, labelText, config)
    config = config or {}
    local searchable = config.searchable == true
    local row
    if self:IsPoolParent(parent) then
        row = (searchable and searchDropdownPool or dropdownPool):Acquire(parent)
    else
        row = ConstructDropdown(parent, searchable)
    end
    ConfigureDropdown(row, labelText, config)
    return row
end
