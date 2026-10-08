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
-- ║  pixelSnap), swaps closure slots (_db, _keys, _onChange, ║
-- ║  _positionKey) read by factory-bound callbacks, and      ║
-- ║  recomputes height.                                      ║
-- ║  ReleaseAll fires from contentRebuildCallbacks on every  ║
-- ║  GUIFrame:RefreshContent so the pool reclaims kits       ║
-- ║  before the page teardown would orphan them.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ipairs = ipairs

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- In screen order; the dropdown keeps an ordered list's order.
local ANCHOR_POINT_OPTIONS = {
    { key = "TOPLEFT",     text = "Top Left" },
    { key = "TOP",         text = "Top" },
    { key = "TOPRIGHT",    text = "Top Right" },
    { key = "LEFT",        text = "Left" },
    { key = "CENTER",      text = "Center" },
    { key = "RIGHT",       text = "Right" },
    { key = "BOTTOMLEFT",  text = "Bottom Left" },
    { key = "BOTTOM",      text = "Bottom" },
    { key = "BOTTOMRIGHT", text = "Bottom Right" },
}

local ANCHOR_FRAME_TYPES = {
    { key = "SCREEN",      text = "Screen Center" },
    { key = "UIPARENT",    text = "Screen (UIParent)" },
    { key = "PLAYERFRAME", text = "Player Frame" },
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
    local posKey = kit._positionKey or "Position"
    if db[posKey] and db[posKey][key] ~= nil then return db[posKey][key] end
    if db[key] ~= nil then return db[key] end
    return default
end

-- NOTE: when a consumer passes config.positionKey for a sub-table (e.g.
-- "RaidPosition"), that sub-table MUST be seeded in the DB (via AceDB
-- defaults) before the card renders. If db[posKey] is nil, position writes
-- silently fall back to the db root, which can clobber unrelated root keys.
-- Root keys (anchorFrameType/ParentFrame/Strata) are unaffected — they always
-- live at the db root regardless of positionKey.
local function kitSetValue(kit, key, val)
    local db = kit._db
    local rootKeys = kit._rootKeys
    if not db then return end
    if rootKeys and rootKeys[key] then
        db[key] = val
    else
        local posKey = kit._positionKey or "Position"
        if db[posKey] then
            db[posKey][key] = val
        else
            db[key] = val
        end
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

    -- Row 3: anchor point dropdowns (always shown)
    local anchorPointRow = GUIFrame:CreateRow(card.content, 36)
    local selfPointDropdown = GUIFrame:CreateDropdown(anchorPointRow, "Anchor From", {
        options = ANCHOR_POINT_OPTIONS,
        value = "CENTER",
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.selfPoint, key)
        end,
    })
    anchorPointRow:AddWidget(selfPointDropdown, 0.5)
    -- Configure relabels this one per render; the text follows the anchor type.
    local anchorPointDropdown = GUIFrame:CreateDropdown(anchorPointRow, "To Screen's", {
        options = ANCHOR_POINT_OPTIONS,
        value = "CENTER",
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kitSetValue(kit, kit._keys.anchorPoint, key)
        end,
    })
    anchorPointRow:AddWidget(anchorPointDropdown, 0.5)
    card:AddRow(anchorPointRow, 36)
    kit.anchorPointRow = anchorPointRow
    kit.selfPointDropdown = selfPointDropdown
    kit.anchorPointDropdown = anchorPointDropdown

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

    -- Bottom row: strata dropdown (shown when showStrata = true).
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
        selfPointDropdown, anchorPointDropdown,
        xSlider, ySlider,
        strataOnlyDropdown,
    }
    kit.anchorButtonWidgets = { selfPointDropdown, anchorPointDropdown }

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
    card.strataWidget = strataOnlyDropdown

    function card:SetPositionWidgetsEnabled(enabled) self:SetEnabled(enabled) end

    -- For a page that rewrites the saved offsets by code while the card shows.
    function card:RefreshOffsets()
        local keys = kit._keys
        if not keys then return end
        local defaults = kit._config and kit._config.defaults or {}
        kit.xSlider:SetValue(kitGetValue(kit, keys.xOffset, defaults.xOffset or 0), true)
        kit.ySlider:SetValue(kitGetValue(kit, keys.yOffset, defaults.yOffset or 0), true)
    end
    function card:SetAnchorsOnlyEnabled(enabled)
        for _, widget in ipairs(kit.anchorButtonWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end

    return kit
end

local positionCardPool = KE.FramePool:New(CreatePositionCardKit)

-- ReleaseAll runs on every GUIFrame:RefreshContent, before the teardown loop
-- releases or orphans the page's children, so the kits are back on the
-- holder by then.
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
    kit._positionKey = config.positionKey or "Position"

    -- Re-anchor card to the scrollChild + yOffset. FramePool.Acquire already
    -- reparented kit.row (the card) to scrollChild but the SetPoint anchors
    -- still point at the pool's hidden holder.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -T.paddingSmall, 0)
    card._yOffset = yOffset or 0
    if card.titleText then card.titleText:SetText(title) end

    -- Refresh theme colors lazily — only when KE._themeVersion has advanced.
    GUIFrame:RefreshKitThemeIfNeeded(kit, kit.allWidgets)

    -- Update anchorPoint label based on currentType (matches original).
    local currentType = kitGetValue(kit, keys.anchorFrameType, defaults.anchorFrameType or "SCREEN")
    local anchorPointLabel = showAnchorFrameType and
        (currentType == "SELECTFRAME" and "To Frame's" or "To Screen's") or
        "To Frame's"
    kit.anchorPointDropdown.label:SetText(anchorPointLabel)

    -- The kit is pooled across pages: without this, a card one page grayed
    -- comes back grayed on a page that has no gray-out of its own.
    card:SetEnabled(true)

    -- Set widget values. CreateDropdown.SetValue accepts (val, silent),
    -- CreateSlider.SetValue accepts (val, silent), CreateCheckbox.toggle
    -- :SetValue accepts (val, instant=true), and EditBox:SetValue doesn't
    -- fire callbacks via OnEnterPressed/OnEditFocusLost.
    kit.anchorTypeDropdown:SetValue(currentType, true)
    kit.frameInput:SetValue(kitGetValue(kit, keys.anchorFrameFrame, ""))
    kit.selfPointDropdown:SetValue(kitGetValue(kit, keys.selfPoint, defaults.selfPoint or "CENTER"), true)
    kit.anchorPointDropdown:SetValue(kitGetValue(kit, keys.anchorPoint, defaults.anchorPoint or "CENTER"), true)

    -- Slider range may be overridden per consumer (DungeonTimersBars/Texts
    -- use ±800 instead of the default ±1000). Apply per render before
    -- SetValue so the value isn't clamped by a stale range. Pass silent=true
    -- so the clamp Blizzard performs when shrinking the range doesn't fire
    -- OnValueChanged → write the clamp value to db before SetValue below
    -- restores the saved value (latent before the FontSettingsCard pool
    -- bug surfaced the same pattern).
    local sliderRange = config.sliderRange or { -1000, 1000 }
    kit.xSlider:SetMinMaxValues(sliderRange[1], sliderRange[2], true)
    kit.ySlider:SetMinMaxValues(sliderRange[1], sliderRange[2], true)
    kit.xSlider:SetValue(kitGetValue(kit, keys.xOffset, defaults.xOffset or 0), true)
    kit.ySlider:SetValue(kitGetValue(kit, keys.yOffset, defaults.yOffset or 0), true)

    local currentStrata = kitGetValue(kit, keys.strata, defaults.strata or "HIGH")
    kit.strataOnlyDropdown:SetValue(currentStrata, true)

    -- Decide which rows are visible for this configuration.
    local showAnchorTypeRow = showAnchorFrameType
    local showSelectFrameRow = showAnchorFrameType and currentType == "SELECTFRAME"
    local showStrataRow = showStrata

    -- Re-anchor visible rows in order, accumulating currentY. Hide invisible
    -- rows. Skip card:Reset (it would orphan the kit's persistent rows).
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
    showRow(kit.anchorPointRow, 36)
    showRow(kit.offsetRow, 36)
    if showStrataRow then
        showRow(kit.strataOnlyRow, T.rowHeightLast)
    else
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
