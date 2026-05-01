-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PositionCard.lua                                    ║
-- ║  Purpose: Position settings card with anchor points,     ║
-- ║  offsets, and strata.                                    ║
-- ║                                                          ║
-- ║  Pooled via KE.FramePool (one global pool). Used in 36+  ║
-- ║  module GUIs; was recreated from scratch per render so   ║
-- ║  page switches leaked ~50 frames per card to UIParent.   ║
-- ║                                                          ║
-- ║  Factory builds the maximal widget set ONCE. Configure   ║
-- ║  shows/hides per-config (showAnchorFrameType / strata /  ║
-- ║  pixelSnap), swaps closure slots (_db, _keys, _onChange) ║
-- ║  read by factory-bound callbacks, and recomputes height. ║
-- ║  ReleaseAll fires from contentRebuildCallbacks on every  ║
-- ║  GUIFrame:RefreshContent so the pool reclaims kits       ║
-- ║  before ClearContent's SetParent(nil) loop orphans them. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

local ANCHOR_DIRECTIONS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"
}

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

local ANCHOR_FRAME_TYPES = {
    { key = "SCREEN",      text = "Screen Center" },
    { key = "UIPARENT",    text = "Screen (UIParent)" },
    { key = "SELECTFRAME", text = "Select Frame" },
}

local STRATA_LIST = {
    { key = "TOOLTIP",           text = "Tooltip" },
    { key = "FULLSCREEN_DIALOG", text = "Fullscreen Dialog" },
    { key = "FULLSCREEN",        text = "Fullscreen" },
    { key = "DIALOG",            text = "Dialog" },
    { key = "HIGH",              text = "High" },
    { key = "MEDIUM",            text = "Medium" },
    { key = "LOW",               text = "Low" },
    { key = "BACKGROUND",        text = "Background" },
}

local SNAP_TOOLTIP = "Snap to Pixel Grid\n\nON: text outlines render crisper at sub-pixel anchors.\nOFF: position sliders apply every tick of movement (recommended while placing the frame).\n\nWorkflow: position with OFF, flip ON when done."
local SNAP_DESC = "ON for crisper text\nOFF for precise positioning"

---------------------------------------------------------------------------------
-- Anchor Buttons widget — kit-bound callback variant
--
-- Accepts the OUTER kit + a slot name. OnClick fires kit[slotName] which
-- Configure swaps per render (e.g. kit._selfPointCallback,
-- kit._anchorPointCallback). Internal "selected" highlighting still works
-- because container.value is updated locally and SetValue swaps it on
-- Configure.
---------------------------------------------------------------------------------

local function CreateAnchorButtons(parent, labelText, outerKit, callbackSlot)
    local buttonSize = 10
    local frameWidth = 101
    local frameHeight = 53
    local titleHeight = 18
    local spacing = 2

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(frameWidth + buttonSize, frameHeight + buttonSize + titleHeight + spacing + 4)

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

    container.value = "CENTER"

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

        button:SetScript("OnClick", function()
            container.value = direction
            for _, btn in pairs(buttons) do
                if container.value == btn.value then
                    btn.tex:SetVertexColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                else
                    btn.tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
                end
            end
            local cb = outerKit[callbackSlot]
            if cb then cb(direction) end
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

        -- Initial color
        tex:SetVertexColor(Theme.textMuted[1], Theme.textMuted[2], Theme.textMuted[3], 1)
        buttons[direction] = button
    end
    container.buttons = buttons

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

    function container:GetValue() return self.value end

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
-- Kit factory — maximal shape: every possible widget for every config combo
---------------------------------------------------------------------------------

-- Helper: get/setValue dispatch over kit slots (mirrors the original
-- closure logic — root-level keys live at db root; Position-keyed values
-- can live in db.Position or fallback to root).
local function kitGetValue(kit, key, default)
    local db = kit._db
    local rootKeys = kit._rootKeys
    if not db then return default end
    if rootKeys and rootKeys[key] then
        if db[key] ~= nil then return db[key] end
        return default
    end
    if db.Position and db.Position[key] ~= nil then return db.Position[key] end
    if db[key] ~= nil then return db[key] end
    return default
end

local function kitSetValue(kit, key, val)
    local db = kit._db
    local rootKeys = kit._rootKeys
    if not db then return end
    if rootKeys and rootKeys[key] then
        db[key] = val
    elseif db.Position then
        db.Position[key] = val
    else
        db[key] = val
    end
    if kit._onChange then kit._onChange() end
end

local function CreatePositionCardKit(holder)
    local kit = {}

    local card = GUIFrame:CreateCard(holder, "Position Settings", 0)
    kit.card = card
    kit.row = card -- KE.FramePool reads kit.row as the root frame

    -- Row 1: Anchored To dropdown (shown only if showAnchorFrameType)
    local anchorTypeRow = GUIFrame:CreateRow(card.content, 36)
    local anchorTypeList = {}
    for _, opt in ipairs(ANCHOR_FRAME_TYPES) do
        anchorTypeList[opt.key] = opt.text
    end
    local anchorTypeDropdown = GUIFrame:CreateDropdown(anchorTypeRow, "Anchored To", {
        options = anchorTypeList,
        value = "SCREEN",
        labelWidth = 70,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.anchorFrameType, key)
            -- Re-render so the SELECTFRAME conditional row appears/disappears.
            -- The 0.25s delay matches the original behavior.
            C_Timer.After(0.25, function()
                if GUIFrame.RefreshContent then GUIFrame:RefreshContent() end
            end)
        end,
    })
    anchorTypeRow:AddWidget(anchorTypeDropdown, 1)
    card:AddRow(anchorTypeRow, 36)
    kit.anchorTypeRow = anchorTypeRow
    kit.anchorTypeDropdown = anchorTypeDropdown

    -- Row 2: Frame input + Select Frame button (shown only if SELECTFRAME)
    local selectFrameRow = GUIFrame:CreateRow(card.content, 36)
    local frameInput = GUIFrame:CreateEditBox(selectFrameRow, "Frame", {
        value = "",
        callback = function(val)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.anchorFrameFrame, val ~= "" and val or nil)
        end,
    })
    selectFrameRow:AddWidget(frameInput, 0.5)
    local selectFrameBtn = GUIFrame:CreateButton(selectFrameRow, "Select Frame", {
        width = 110,
        height = 24,
        callback = function()
            if not kit._db or not kit._keys then return end
            if KE.FrameChooser then
                KE.FrameChooser:Start(function(frameName, isPreview)
                    if frameName then
                        frameInput:SetValue(frameName)
                        if not isPreview then
                            kitSetValue(kit, kit._keys.anchorFrameFrame, frameName)
                        end
                    end
                end, kitGetValue(kit, kit._keys.anchorFrameFrame, ""))
            end
        end,
    })
    selectFrameRow:AddWidget(selectFrameBtn, 0.5, nil, 0, -14)
    card:AddRow(selectFrameRow, 36)
    kit.selectFrameRow = selectFrameRow
    kit.frameInput = frameInput
    kit.selectFrameBtn = selectFrameBtn

    -- Row 3: Anchor point selectors (always shown)
    local anchorButtonRow = GUIFrame:CreateRow(card.content, 80)
    local selfPointWidget = CreateAnchorButtons(anchorButtonRow, "Anchor From", kit, "_selfPointCallback")
    anchorButtonRow:AddWidget(selfPointWidget, 0.5)
    local anchorPointWidget = CreateAnchorButtons(anchorButtonRow, "To Frame's", kit, "_anchorPointCallback")
    anchorButtonRow:AddWidget(anchorPointWidget, 0.5)
    card:AddRow(anchorButtonRow, 80)
    kit.anchorButtonRow = anchorButtonRow
    kit.selfPointWidget = selfPointWidget
    kit.anchorPointWidget = anchorPointWidget

    -- Row 4: X/Y offset sliders (always shown)
    local offsetRow = GUIFrame:CreateRow(card.content, 36)
    local xSlider = GUIFrame:CreateSlider(offsetRow, "X Offset", {
        min = -1000, max = 1000, step = 1, value = 0, labelWidth = 55,
        callback = function(val)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.xOffset, val)
        end,
    })
    offsetRow:AddWidget(xSlider, 0.5)
    local ySlider = GUIFrame:CreateSlider(offsetRow, "Y Offset", {
        min = -1000, max = 1000, step = 1, value = 0, labelWidth = 55,
        callback = function(val)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.yOffset, val)
        end,
    })
    offsetRow:AddWidget(ySlider, 0.5)
    card:AddRow(offsetRow, 36)
    kit.offsetRow = offsetRow
    kit.xSlider = xSlider
    kit.ySlider = ySlider

    -- Bottom row: three mutually-exclusive layouts (combined / strata-only /
    -- snap-only). Build all three; Configure shows the right one based on
    -- showStrata + showPixelSnap. Storing all variants in the kit keeps the
    -- factory simple at the cost of a few extra widgets per kit; only one is
    -- ever visible at a time.

    -- Combined: strata (left) + snap toggle (right with inline desc)
    local combinedRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local comboStrataDropdown = GUIFrame:CreateDropdown(combinedRow, "Strata", {
        options = STRATA_LIST,
        value = "HIGH",
        labelWidth = 39,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.strata, key)
        end,
    })
    combinedRow:AddWidget(comboStrataDropdown, 0.5, 20)
    local comboSnapToggle = GUIFrame:CreateCheckbox(combinedRow, "Snap to Pixel Grid", {
        value = false,
        tooltip = SNAP_TOOLTIP,
        callback = function(value)
            if not kit._db then return end
            kit._db.SnapToPixelGrid = value
            if kit._onChange then kit._onChange() end
        end,
    })
    combinedRow:AddWidget(comboSnapToggle, 0.5)
    -- Inline 2-line muted descriptor on the snap toggle
    do
        local snapDesc = comboSnapToggle:CreateFontString(nil, "OVERLAY")
        snapDesc:SetPoint("TOPLEFT", comboSnapToggle, "TOPLEFT", 60, -10)
        snapDesc:SetPoint("BOTTOMRIGHT", comboSnapToggle, "BOTTOMRIGHT", 0, 0)
        KE:ApplyThemeFont(snapDesc, "small")
        snapDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
        snapDesc:SetJustifyH("LEFT")
        snapDesc:SetJustifyV("MIDDLE")
        snapDesc:SetWordWrap(true)
        snapDesc:SetText(SNAP_DESC)
    end
    card:AddRow(combinedRow, Theme.rowHeightLast, 0)
    kit.combinedRow = combinedRow
    kit.comboStrataDropdown = comboStrataDropdown
    kit.comboSnapToggle = comboSnapToggle

    -- Snap-only: full-width snap toggle with inline descriptor
    local snapOnlyRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local snapOnlyToggle = GUIFrame:CreateCheckbox(snapOnlyRow, "Snap to Pixel Grid", {
        value = false,
        tooltip = SNAP_TOOLTIP,
        callback = function(value)
            if not kit._db then return end
            kit._db.SnapToPixelGrid = value
            if kit._onChange then kit._onChange() end
        end,
    })
    snapOnlyRow:AddWidget(snapOnlyToggle, 1)
    do
        local snapDesc = snapOnlyToggle:CreateFontString(nil, "OVERLAY")
        snapDesc:SetPoint("TOPLEFT", snapOnlyToggle, "TOPLEFT", 60, -10)
        snapDesc:SetPoint("BOTTOMRIGHT", snapOnlyToggle, "BOTTOMRIGHT", 0, 0)
        KE:ApplyThemeFont(snapDesc, "small")
        snapDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
        snapDesc:SetJustifyH("LEFT")
        snapDesc:SetJustifyV("MIDDLE")
        snapDesc:SetWordWrap(true)
        snapDesc:SetText(SNAP_DESC)
    end
    card:AddRow(snapOnlyRow, Theme.rowHeightLast, 0)
    kit.snapOnlyRow = snapOnlyRow
    kit.snapOnlyToggle = snapOnlyToggle

    -- Strata-only: full-width strata dropdown
    local strataOnlyRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local strataOnlyDropdown = GUIFrame:CreateDropdown(strataOnlyRow, "Strata", {
        options = STRATA_LIST,
        value = "HIGH",
        labelWidth = 39,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.strata, key)
        end,
    })
    strataOnlyRow:AddWidget(strataOnlyDropdown, 1)
    card:AddRow(strataOnlyRow, Theme.rowHeightLast, 0)
    kit.strataOnlyRow = strataOnlyRow
    kit.strataOnlyDropdown = strataOnlyDropdown

    -- Cache post-build currentY so Configure can reset to it after manipulating
    -- conditional row visibility. card.rows[*] is the order in which AddRow
    -- inserted them; we keep that order stable and just hide/show.
    kit._maxCurrentY = card.currentY

    -- Track widgets for SetEnabled compatibility (the original API exposed
    -- card.positionWidgets and card.AnchorButtonWidgets; consumers like
    -- WidgetStateManager pass these to RegisterGroup).
    kit.allWidgets = {
        anchorTypeDropdown, frameInput, selectFrameBtn,
        selfPointWidget, anchorPointWidget,
        xSlider, ySlider,
        comboStrataDropdown, comboSnapToggle,
        snapOnlyToggle, strataOnlyDropdown,
    }
    kit.anchorButtonWidgets = { selfPointWidget, anchorPointWidget }

    -- Override card:SetEnabled to also walk the kit's widgets. Default
    -- card:SetEnabled (from GUI-Core) only does alpha + the click-blocker
    -- overlay. We additionally want each widget's individual disabled state
    -- (grays the slider/dropdown text, blocks anchor button clicks even if
    -- the overlay is bypassed).
    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        for _, widget in ipairs(kit.allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            elseif widget.SetDisabled then
                widget:SetDisabled(not enabled)
            end
        end
    end

    -- Compatibility shims for callers that used to read these directly off
    -- the card. The original implementation exposed positionWidgets and
    -- AnchorButtonWidgets as card-level fields used by WidgetStateManager.
    card.positionWidgets = kit.allWidgets
    card.AnchorButtonWidgets = kit.anchorButtonWidgets

    function card:SetPositionWidgetsEnabled(enabled) self:SetEnabled(enabled) end
    function card:SetAnchorsOnlyEnabled(enabled)
        for _, widget in ipairs(kit.anchorButtonWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end

    return kit
end

local positionCardPool = KE.FramePool:New(CreatePositionCardKit)

-- Register pool ReleaseAll on every GUIFrame:RefreshContent. Fires before
-- the existing scrollChild SetParent(nil) loop, so pooled kits get back to
-- the holder before they'd otherwise be orphaned to UIParent.
GUIFrame:RegisterContentRebuildCallback("__PositionCardPool", function()
    positionCardPool:ReleaseAll()
end)

---------------------------------------------------------------------------------
-- Configure: re-anchor card, swap closure slots, set widget values silently,
-- show/hide rows per config, recompute card height.
---------------------------------------------------------------------------------

local function ConfigurePositionCardKit(kit, scrollChild, yOffset, config)
    local T = Theme
    local card = kit.card

    local title = config.title or "Position Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local defaults = config.defaults or {}
    local onChange = config.onChangeCallback
    local showAnchorFrameType = config.showAnchorFrameType ~= false
    local showStrata = config.showStrata == true
    local showPixelSnap = config.showPixelSnap == true

    -- Resolve keys map. Keep the same defaults as the original implementation
    -- so consumers that only override a subset still hit the right db slots.
    local keys = {
        anchorFrameType = dbKeys.anchorFrameType or "anchorFrameType",
        anchorFrameFrame = dbKeys.anchorFrameFrame or "ParentFrame",
        selfPoint = dbKeys.selfPoint or "AnchorFrom",
        anchorPoint = dbKeys.anchorPoint or "AnchorTo",
        xOffset = dbKeys.xOffset or "XOffset",
        yOffset = dbKeys.yOffset or "YOffset",
        strata = dbKeys.strata or "Strata",
    }
    local rootKeys = {
        [keys.anchorFrameType] = true,
        [keys.anchorFrameFrame] = true,
        [keys.strata] = true,
    }

    -- Swap kit slots BEFORE any widget SetValue. The factory-bound callbacks
    -- read these slots; values set via :SetValue() are programmatic and
    -- shouldn't fire callbacks, but if any widget bypasses silent we'd at
    -- least be reading the new db.
    kit._db = db
    kit._keys = keys
    kit._rootKeys = rootKeys
    kit._onChange = onChange
    kit._config = config

    -- Anchor button callbacks read kit._selfPointCallback / _anchorPointCallback
    -- on click. Closures here are minimal — they just call kitSetValue with
    -- the resolved key.
    kit._selfPointCallback = function(val) kitSetValue(kit, keys.selfPoint, val) end
    kit._anchorPointCallback = function(val) kitSetValue(kit, keys.anchorPoint, val) end

    -- Re-anchor card to the scrollChild + yOffset. FramePool.Acquire already
    -- reparented kit.row (the card) to scrollChild but the SetPoint anchors
    -- still point at the pool's hidden holder.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -T.paddingSmall, 0)
    card._yOffset = yOffset or 0
    if card.titleText then card.titleText:SetText(title) end

    -- Update anchorPoint label based on currentType (matches original).
    local currentType = kitGetValue(kit, keys.anchorFrameType, defaults.anchorFrameType or "SCREEN")
    local anchorPointLabel = showAnchorFrameType and
        (currentType == "SELECTFRAME" and "To Frame's" or "To Screen's") or
        "To Frame's"
    if kit.anchorPointWidget and kit.anchorPointWidget.label then
        kit.anchorPointWidget.label:SetText(anchorPointLabel)
    end

    -- Set widget values. CreateDropdown.SetValue accepts (val, silent),
    -- CreateSlider.SetValue accepts (val, silent), CreateCheckbox.toggle
    -- :SetValue accepts (val, instant=true), AnchorButton:SetValue + EditBox
    -- :SetValue don't fire callbacks via OnEnterPressed/OnEditFocusLost.
    kit.anchorTypeDropdown:SetValue(currentType, true)
    kit.frameInput:SetValue(kitGetValue(kit, keys.anchorFrameFrame, ""))
    kit.selfPointWidget:SetValue(kitGetValue(kit, keys.selfPoint, defaults.selfPoint or "CENTER"))
    kit.anchorPointWidget:SetValue(kitGetValue(kit, keys.anchorPoint, defaults.anchorPoint or "CENTER"))
    kit.xSlider:SetValue(kitGetValue(kit, keys.xOffset, defaults.xOffset or 0), true)
    kit.ySlider:SetValue(kitGetValue(kit, keys.yOffset, defaults.yOffset or 0), true)

    local currentStrata = kitGetValue(kit, keys.strata, defaults.strata or "HIGH")
    kit.comboStrataDropdown:SetValue(currentStrata, true)
    kit.strataOnlyDropdown:SetValue(currentStrata, true)
    if kit.comboSnapToggle.toggle and kit.comboSnapToggle.toggle.SetValue then
        kit.comboSnapToggle.toggle:SetValue(db and db.SnapToPixelGrid == true, true)
    end
    if kit.snapOnlyToggle.toggle and kit.snapOnlyToggle.toggle.SetValue then
        kit.snapOnlyToggle.toggle:SetValue(db and db.SnapToPixelGrid == true, true)
    end

    -- Decide which rows are visible for this configuration.
    local showAnchorTypeRow = showAnchorFrameType
    local showSelectFrameRow = showAnchorFrameType and currentType == "SELECTFRAME"
    local showCombined = showStrata and showPixelSnap
    local showSnapOnly = showPixelSnap and not showStrata
    local showStrataOnly = showStrata and not showPixelSnap

    -- Re-anchor visible rows in order, accumulating currentY. Hide invisible
    -- rows. Skip card:Reset (it would orphan persistent rows to UIParent).
    -- We rebuild card.rows inline so card:UpdateHeight reads the right state.
    local function showRow(row, height)
        row:Show()
        row:ClearAllPoints()
        row:SetParent(card.content)
        row:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -card.currentY)
        row:SetPoint("TOPRIGHT", card.content, "TOPRIGHT", 0, -card.currentY)
        card.currentY = card.currentY + height + T.paddingSmall
    end

    card.currentY = 0
    if card.rows then for i = #card.rows, 1, -1 do card.rows[i] = nil end end

    if showAnchorTypeRow then
        showRow(kit.anchorTypeRow, 36)
    else
        kit.anchorTypeRow:Hide()
    end
    if showSelectFrameRow then
        showRow(kit.selectFrameRow, 36)
    else
        kit.selectFrameRow:Hide()
    end
    showRow(kit.anchorButtonRow, 80)
    showRow(kit.offsetRow, 36)
    if showCombined then
        showRow(kit.combinedRow, T.rowHeightLast)
        kit.snapOnlyRow:Hide()
        kit.strataOnlyRow:Hide()
    elseif showSnapOnly then
        showRow(kit.snapOnlyRow, T.rowHeightLast)
        kit.combinedRow:Hide()
        kit.strataOnlyRow:Hide()
    elseif showStrataOnly then
        showRow(kit.strataOnlyRow, T.rowHeightLast)
        kit.combinedRow:Hide()
        kit.snapOnlyRow:Hide()
    else
        kit.combinedRow:Hide()
        kit.snapOnlyRow:Hide()
        kit.strataOnlyRow:Hide()
    end

    card.content:SetHeight(card.currentY > 0 and card.currentY or 1)
    card:UpdateHeight()

    return card
end

---------------------------------------------------------------------------------
-- Public entry: CreatePositionCard
---------------------------------------------------------------------------------

function GUIFrame:CreatePositionCard(scrollChild, yOffset, config)
    config = config or {}
    local kit = positionCardPool:Acquire(scrollChild)
    ConfigurePositionCardKit(kit, scrollChild, yOffset, config)
    return kit.card, yOffset + kit.card:GetContentHeight() + Theme.paddingSmall
end
