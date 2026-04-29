-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PositionCard.lua                                    ║
-- ║  Purpose: Position settings card with anchor points,     ║
-- ║  offsets, and strata.                                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme


local table_insert = table.insert
local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- Direction order (matches visual layout)
local ANCHOR_DIRECTIONS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
}

-- Direction display names for tooltips
local DIRECTION_NAMES = {
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}

-- Anchor frame type options
local ANCHOR_FRAME_TYPES = {
    { key = "SCREEN",      text = "Screen Center" },
    { key = "UIPARENT",    text = "Screen (UIParent)" },
    { key = "SELECTFRAME", text = "Select Frame" },
}

---------------------------------------------------------------------------------
-- Anchor Buttons
---------------------------------------------------------------------------------
local function CreateAnchorButtons(parent, labelText, value, callback)
    local buttonSize = 10
    local frameWidth = 101
    local frameHeight = 53
    local titleHeight = 18
    local spacing = 2

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(frameWidth + buttonSize, frameHeight + buttonSize + titleHeight + spacing + 4)

    -- Title label
    local label = container:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOP", container, "TOP", 0, 2)
    label:SetHeight(titleHeight)
    label:SetJustifyH("CENTER")
    if KE.ApplyThemeFont then
        KE:ApplyThemeFont(label, "small")
    else
        label:SetFontObject("GameFontNormalSmall")
    end
    label:SetText(labelText or "")
    label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    container.label = label

    -- Background with border
    local background = CreateFrame("Frame", nil, container, "BackdropTemplate")
    background:SetSize(frameWidth, frameHeight)
    background:SetPoint("TOP", container, "TOP", 0, -(titleHeight + spacing))
    background:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    background:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
    background:SetBackdropBorderColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
    container.background = background

    -- Current value
    container.value = value or "CENTER"

    -- Create the 9 anchor buttons
    local buttons = {}
    for _, direction in ipairs(ANCHOR_DIRECTIONS) do
        local button = CreateFrame("Button", nil, container)
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("CENTER", background, direction)

        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
        button.tex = tex
        button.value = direction

        -- Update color based on selection
        local function UpdateButtonColor()
            if container.value == direction then
                tex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            else
                tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
            end
        end

        button:SetScript("OnClick", function()
            container.value = direction
            -- Update all buttons
            for _, btn in pairs(buttons) do
                if container.value == btn.value then
                    btn.tex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    btn.tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
                end
            end
            if callback then callback(direction) end
        end)

        button:SetScript("OnEnter", function(self)
            if not container.disabled then
                self.tex:SetVertexColor(Theme.accentHover[1], Theme.accentHover[2], Theme.accentHover[3], 1)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(DIRECTION_NAMES[direction] or direction, 1, 0.82, 0)
            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function(self)
            if not container.disabled then
                if container.value == direction then
                    self.tex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    self.tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
                end
            end
            GameTooltip:Hide()
        end)

        UpdateButtonColor()
        buttons[direction] = button
    end
    container.buttons = buttons

    -- SetValue method
    function container:SetValue(val)
        self.value = val
        for direction, btn in pairs(self.buttons) do
            if val == direction then
                btn.tex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
            else
                btn.tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
            end
        end
    end

    -- GetValue method
    function container:GetValue()
        return self.value
    end

    -- SetEnabled method
    function container:SetEnabled(enabled)
        self.disabled = not enabled
        if enabled then
            self:SetAlpha(1)
            for _, btn in pairs(self.buttons) do
                btn:EnableMouse(true)
            end
        else
            self:SetAlpha(0.4)
            for _, btn in pairs(self.buttons) do
                btn:EnableMouse(false)
            end
        end
    end

    return container
end

---------------------------------------------------------------------------------
-- Card Creation
---------------------------------------------------------------------------------
function GUIFrame:CreatePositionCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Position Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local defaults = config.defaults or {}
    local onChange = config.onChangeCallback
    local showAnchorFrameType = config.showAnchorFrameType ~= false
    local showStrata = config.showStrata == true
    local showPixelSnap = config.showPixelSnap == true
    local sliderRange = config.sliderRange or { -1000, 1000 }

    -- Map field names to actual db keys
    local keys = {
        anchorFrameType = dbKeys.anchorFrameType or "anchorFrameType",
        anchorFrameFrame = dbKeys.anchorFrameFrame or "ParentFrame",
        selfPoint = dbKeys.selfPoint or "AnchorFrom",
        anchorPoint = dbKeys.anchorPoint or "AnchorTo",
        xOffset = dbKeys.xOffset or "XOffset",
        yOffset = dbKeys.yOffset or "YOffset",
        strata = dbKeys.strata or "Strata",
    }

    -- Keys that are stored at root level (not in Position table)
    local rootKeys = {
        [keys.anchorFrameType] = true,
        [keys.anchorFrameFrame] = true,
        [keys.strata] = true,
    }

    -- Helper to get value from db (handles nested Position table or flat)
    local function getValue(key, default)
        -- Root-level keys are always at db root
        if rootKeys[key] then
            if db[key] ~= nil then
                return db[key]
            end
            return default
        end
        -- Position-related keys check Position table first, then root
        if db.Position and db.Position[key] ~= nil then
            return db.Position[key]
        elseif db[key] ~= nil then
            return db[key]
        end
        return default
    end

    -- Helper to set value in db
    local function setValue(key, val)
        -- Root-level keys are always saved at db root
        if rootKeys[key] then
            db[key] = val
        elseif db.Position then
            -- Position-related keys go in Position table if it exists
            db.Position[key] = val
        else
            db[key] = val
        end
        if onChange then onChange() end
    end

    -- Track widgets for enable/disable
    local widgets = {}
    local AnchorButtonwidgets = {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    -- Get current anchor type for conditional UI
    local currentType = getValue(keys.anchorFrameType, defaults.anchorFrameType or "SCREEN")

    -- Row 1: Anchored To dropdown
    if showAnchorFrameType then
        local row1 = GUIFrame:CreateRow(card.content, 36)

        local anchorTypeList = {}
        for _, opt in ipairs(ANCHOR_FRAME_TYPES) do
            anchorTypeList[opt.key] = opt.text
        end

        local anchorTypeDropdown = GUIFrame:CreateDropdown(row1, "Anchored To", {
            options = anchorTypeList,
            value = currentType,
            labelWidth = 70,
            callback = function(key)
                setValue(keys.anchorFrameType, key)
                C_Timer.After(0.25, function()
                    GUIFrame:RefreshContent()
                end)
            end,
        })
        row1:AddWidget(anchorTypeDropdown, 1)
        table_insert(widgets, anchorTypeDropdown)
        card:AddRow(row1, 36)

        -- Row 2: Frame input + Select Frame button (only if SELECTFRAME)
        if currentType == "SELECTFRAME" then
            local row2 = GUIFrame:CreateRow(card.content, 36)

            local frameInput = GUIFrame:CreateEditBox(row2, "Frame", {
                value = getValue(keys.anchorFrameFrame, ""),
                callback = function(val)
                    setValue(keys.anchorFrameFrame, val ~= "" and val or nil)
                end,
            })
            row2:AddWidget(frameInput, 0.5)
            table_insert(widgets, frameInput)

            local selectFrameBtn = GUIFrame:CreateButton(row2, "Select Frame", {
                width = 110,
                height = 24,
                callback = function()
                    if KE.FrameChooser then
                        KE.FrameChooser:Start(function(frameName, isPreview)
                            if frameName then
                                frameInput:SetValue(frameName)
                                if not isPreview then
                                    setValue(keys.anchorFrameFrame, frameName)
                                end
                            end
                        end, getValue(keys.anchorFrameFrame, ""))
                    end
                end,
            })
            row2:AddWidget(selectFrameBtn, 0.5, nil, 0, -14)
            table_insert(widgets, selectFrameBtn)
            card:AddRow(row2, 36)
        end
    end

    -- Row 3: Anchor point selectors
    local row3 = GUIFrame:CreateRow(card.content, 80)

    local selfPointValue = getValue(keys.selfPoint, defaults.selfPoint or "CENTER")
    local selfPointWidget = CreateAnchorButtons(row3, "Anchor From", selfPointValue, function(val)
        setValue(keys.selfPoint, val)
    end)
    row3:AddWidget(selfPointWidget, 0.5)
    table_insert(widgets, selfPointWidget)
    table_insert(AnchorButtonwidgets, selfPointWidget)

    local anchorPointLabel = showAnchorFrameType and
        (currentType == "SELECTFRAME" and "To Frame's" or "To Screen's") or
        "To Frame's"
    local anchorPointValue = getValue(keys.anchorPoint, defaults.anchorPoint or "CENTER")
    local anchorPointWidget = CreateAnchorButtons(row3, anchorPointLabel, anchorPointValue, function(val)
        setValue(keys.anchorPoint, val)
    end)
    row3:AddWidget(anchorPointWidget, 0.5)
    table_insert(widgets, anchorPointWidget)
    table_insert(AnchorButtonwidgets, anchorPointWidget)
    card:AddRow(row3, 80)

    -- Row 4: X and Y offset sliders
    local row4 = GUIFrame:CreateRow(card.content, 36)

    local xSlider = GUIFrame:CreateSlider(row4, "X Offset", {
        min = sliderRange[1], max = sliderRange[2], step = 1,
        value = getValue(keys.xOffset, defaults.xOffset or 0),
        labelWidth = 55,
        callback = function(val)
            setValue(keys.xOffset, val)
        end,
    })
    row4:AddWidget(xSlider, 0.5)
    table_insert(widgets, xSlider)

    local ySlider = GUIFrame:CreateSlider(row4, "Y Offset", {
        min = sliderRange[1], max = sliderRange[2], step = 1,
        value = getValue(keys.yOffset, defaults.yOffset or 0),
        labelWidth = 55,
        callback = function(val)
            setValue(keys.yOffset, val)
        end,
    })
    row4:AddWidget(ySlider, 0.5)
    table_insert(widgets, ySlider)
    card:AddRow(row4, 36)

    -- Strata dropdown options (ordered highest → lowest)
    local strataList = {
        { key = "TOOLTIP",           text = "Tooltip" },
        { key = "FULLSCREEN_DIALOG", text = "Fullscreen Dialog" },
        { key = "FULLSCREEN",        text = "Fullscreen" },
        { key = "DIALOG",            text = "Dialog" },
        { key = "HIGH",              text = "High" },
        { key = "MEDIUM",            text = "Medium" },
        { key = "LOW",               text = "Low" },
        { key = "BACKGROUND",        text = "Background" },
    }

    local snapTooltip = "Snap to Pixel Grid\n\nON: text outlines render crisper at sub-pixel anchors.\nOFF: position sliders apply every tick of movement (recommended while placing the frame).\n\nWorkflow: position with OFF, flip ON when done."
    local snapDescText = "ON for crisper text\nOFF for precise positioning"

    -- Helper: pin a 2-line muted descriptor to the right of a toggle widget.
    -- Toggle box is 48px wide at the toggle frame's left edge; descriptor
    -- starts at x=60 (clear of the box) and fills the rest of the toggle frame.
    local function AddInlineSnapDesc(parentToggle)
        local snapDesc = parentToggle:CreateFontString(nil, "OVERLAY")
        snapDesc:SetPoint("TOPLEFT", parentToggle, "TOPLEFT", 60, -10)
        snapDesc:SetPoint("BOTTOMRIGHT", parentToggle, "BOTTOMRIGHT", 0, 0)
        KE:ApplyThemeFont(snapDesc, "small")
        snapDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
        snapDesc:SetJustifyH("LEFT")
        snapDesc:SetJustifyV("MIDDLE")
        snapDesc:SetWordWrap(true)
        snapDesc:SetText(snapDescText)
    end

    -- Combined row: strata (left half) | snap toggle + inline descriptor (right half)
    if showStrata and showPixelSnap then
        local rowCombined = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)

        local currentStrata = getValue(keys.strata, defaults.strata or "HIGH")
        local strataDropdown = GUIFrame:CreateDropdown(rowCombined, "Strata", {
            options = strataList,
            value = currentStrata,
            labelWidth = 39,
            callback = function(key)
                setValue(keys.strata, key)
            end,
        })
        rowCombined:AddWidget(strataDropdown, 0.5, 20)
        table_insert(widgets, strataDropdown)

        local currentSnap = db.SnapToPixelGrid == true
        local snapToggle = GUIFrame:CreateCheckbox(rowCombined, "Snap to Pixel Grid", {
            value = currentSnap,
            tooltip = snapTooltip,
            callback = function(value)
                db.SnapToPixelGrid = value
                if onChange then onChange() end
            end,
        })
        rowCombined:AddWidget(snapToggle, 0.5)
        table_insert(widgets, snapToggle)
        AddInlineSnapDesc(snapToggle)
        card:AddRow(rowCombined, Theme.rowHeightLast, 0)

    -- Snap-only path: full-width toggle row with inline descriptor
    elseif showPixelSnap then
        local row5 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local currentSnap = db.SnapToPixelGrid == true
        local snapToggle = GUIFrame:CreateCheckbox(row5, "Snap to Pixel Grid", {
            value = currentSnap,
            tooltip = snapTooltip,
            callback = function(value)
                db.SnapToPixelGrid = value
                if onChange then onChange() end
            end,
        })
        row5:AddWidget(snapToggle, 1)
        table_insert(widgets, snapToggle)
        AddInlineSnapDesc(snapToggle)
        card:AddRow(row5, Theme.rowHeightLast, 0)

    -- Strata-only path: full-width dropdown at the bottom
    elseif showStrata then
        local row6 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local currentStrata = getValue(keys.strata, defaults.strata or "HIGH")
        local strataDropdown = GUIFrame:CreateDropdown(row6, "Strata", {
            options = strataList,
            value = currentStrata,
            labelWidth = 39,
            callback = function(key)
                setValue(keys.strata, key)
            end,
        })
        row6:AddWidget(strataDropdown, 1)
        table_insert(widgets, strataDropdown)
        card:AddRow(row6, Theme.rowHeightLast, 0)
    end

    -- Store widgets for external enable/disable
    card.positionWidgets = widgets
    card.AnchorButtonWidgets = AnchorButtonwidgets

    -- SetEnabled method for the card
    function card:SetEnabled(enabled)
        -- Apply visual disabled state to the card itself
        if enabled then
            self:SetAlpha(1)
            if self.header then self.header:SetAlpha(1) end
            if self.titleText then self.titleText:SetAlpha(1) end
        else
            self:SetAlpha(0.5)
            if self.header then self.header:SetAlpha(0.5) end
            if self.titleText then self.titleText:SetAlpha(0.5) end
        end

        -- Disable all internal widgets
        for _, widget in ipairs(self.positionWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            elseif widget.SetDisabled then
                widget:SetDisabled(not enabled)
            end
        end
    end
    function card:SetPositionWidgetsEnabled(enabled)
        self:SetEnabled(enabled)
    end
    function card:SetAnchorsOnlyEnabled(enabled)
        for _, widget in ipairs(self.AnchorButtonWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            end
        end
    end

    return card, yOffset + card:GetContentHeight() + Theme.paddingSmall
end
