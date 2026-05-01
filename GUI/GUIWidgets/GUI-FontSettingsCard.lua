-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FontSettingsCard.lua                                ║
-- ║  Purpose: Font face / size / outline / shadow card.      ║
-- ║  Reusable across all text-displaying modules.            ║
-- ║                                                          ║
-- ║  Pooled via KE.FramePool for the simple shape (font      ║
-- ║  dropdown + outline dropdown + single size slider) which ║
-- ║  covers ~25 of 27 call sites. The two outlier shapes —   ║
-- ║  fontSizes-array (HealerMana) and extraSlider            ║
-- ║  (CombatTexts) — fall back to a legacy CreateCard path,  ║
-- ║  preserving their existing layout. Public API            ║
-- ║  CreateFontSettingsCard signature unchanged so call      ║
-- ║  sites need no migration.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local pairs = pairs
local ipairs = ipairs

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function BuildFontList()
    local list = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            list[name] = name
        end
    else
        list["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    return list
end

-- Outline option list — built per Configure since includeSoftOutline can vary
-- across call sites that share the same kit instance from the pool.
local function BuildOutlineOptions(includeSoftOutline)
    local opts = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    if includeSoftOutline then
        table_insert(opts, { key = "SOFTOUTLINE", text = "Soft" })
    end
    return opts
end

-- DB getter / setter helpers that support nested "a.b.c" keys. Match the
-- legacy CreateFontSettingsCard behavior — a couple of call sites use this.
local function GetDbValue(db, key, default)
    if not db or key == nil then return default end
    if key:find("%.") then
        local parts = { strsplit(".", key) }
        local current = db
        for _, part in ipairs(parts) do
            if current[part] == nil then return default end
            current = current[part]
        end
        return current
    end
    if db[key] ~= nil then return db[key] end
    return default
end

local function SetDbValue(db, key, val)
    if not db or key == nil then return end
    if key:find("%.") then
        local parts = { strsplit(".", key) }
        local current = db
        for i = 1, #parts - 1 do
            current = current[parts[i]]
        end
        current[parts[#parts]] = val
    else
        db[key] = val
    end
end

---------------------------------------------------------------------------------
-- Kit factory: card + font/outline dropdowns + single font-size slider.
-- Callbacks read kit slots (_db, _keys, _onChange) that Configure swaps per
-- render. Built ONCE under the pool's hidden holder and reused across renders.
---------------------------------------------------------------------------------

local function CreateFontSettingsCardKit(holder)
    local kit = {}

    local card = GUIFrame:CreateCard(holder, "Font Settings", 0)
    kit.card = card
    kit.row = card -- KE.FramePool reads kit.row as the root frame

    -- Row 1: font face dropdown + outline dropdown
    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)

    local fontDropdown = GUIFrame:CreateDropdown(row1, "Font", {
        options = { ["Friz Quadrata TT"] = "Friz Quadrata TT" },
        value = "Friz Quadrata TT",
        searchable = true,
        isFontPreview = true,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            SetDbValue(kit._db, kit._keys.fontFace, key)
            if kit._onChange then kit._onChange() end
        end,
    })
    row1:AddWidget(fontDropdown, 0.5)

    local outlineDropdown = GUIFrame:CreateDropdown(row1, "Outline", {
        options = BuildOutlineOptions(false),
        value = "OUTLINE",
        callback = function(key)
            if not kit._db or not kit._keys then return end
            SetDbValue(kit._db, kit._keys.fontOutline, key)
            if kit._onChange then kit._onChange() end
        end,
    })
    row1:AddWidget(outlineDropdown, 0.5)
    card:AddRow(row1, Theme.rowHeight)

    -- Row 2: font size slider (single, full-width — covers 25/27 call sites).
    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local fontSizeSlider = GUIFrame:CreateSlider(row2, "Font Size", {
        min = 8,
        max = 72,
        step = 1,
        value = 18,
        labelWidth = 60,
        callback = function(val)
            if not kit._db or not kit._keys then return end
            SetDbValue(kit._db, kit._keys.fontSize, val)
            if kit._onChange then kit._onChange() end
        end,
    })
    row2:AddWidget(fontSizeSlider, 1)
    card:AddRow(row2, Theme.rowHeightLast, 0)

    kit.fontDropdown = fontDropdown
    kit.outlineDropdown = outlineDropdown
    kit.fontSizeSlider = fontSizeSlider

    -- Compatibility shim — original CreateFontSettingsCard exposed
    -- card.fontWidgets and SetEnabled walked it. Keep the contract.
    local fontWidgets = { fontDropdown, outlineDropdown, fontSizeSlider }
    card.fontWidgets = fontWidgets

    -- Override card:SetEnabled to also walk font widgets, on top of the
    -- default alpha + click-blocker overlay from GUI-Core's CreateCard.
    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        for _, widget in ipairs(fontWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end

    return kit
end

local fontSettingsCardPool = KE.FramePool:New(CreateFontSettingsCardKit)

GUIFrame:RegisterContentRebuildCallback("__FontSettingsCardPool", function()
    fontSettingsCardPool:ReleaseAll()
end)

---------------------------------------------------------------------------------
-- Configure: re-anchor card, swap slots, refresh LSM-derived options, set values
---------------------------------------------------------------------------------

local function ConfigureFontSettingsCardKit(kit, scrollChild, yOffset, config)
    local T = Theme
    local card = kit.card

    local title = config.title or "Font Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback
    local fontSizeRange = config.fontSizeRange or { 8, 72 }
    local includeSoftOutline = config.includeSoftOutline == true

    local keys = {
        fontFace = dbKeys.fontFace or "FontFace",
        fontSize = dbKeys.fontSize or "FontSize",
        fontOutline = dbKeys.fontOutline or "FontOutline",
    }

    -- Swap kit slots BEFORE widget SetValue so callbacks see the new state
    -- if anything fires synchronously during the refresh below.
    kit._db = db
    kit._keys = keys
    kit._onChange = onChange

    -- Re-anchor card to the new scrollChild position. Acquire reparented the
    -- root frame (kit.row = card) but its TOPLEFT/RIGHT anchors still point
    -- at the pool's hidden holder.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -T.paddingSmall, 0)
    card._yOffset = yOffset or 0
    if card.titleText then card.titleText:SetText(title) end

    -- Rebuild the LSM font list per Configure so a font media addon that
    -- loaded after the first render gets picked up. Cheap when the dropdown's
    -- item buttons aren't already created (collapsed state).
    kit.fontDropdown:SetOptions(BuildFontList())

    -- Outline options vary per call site (includeSoftOutline). Rebuild per
    -- Configure so a kit can switch between Soft-supporting and not across
    -- different module pages that reuse the same instance.
    kit.outlineDropdown:SetOptions(BuildOutlineOptions(includeSoftOutline))

    -- Note: searchable=false is handled at the public-API level by routing
    -- to the legacy build-fresh path. The pooled factory always builds with
    -- searchable=true since KEDropdown's searchable is fixed at construction.

    -- Set values silently (silent flag suppresses callback).
    kit.fontDropdown:SetValue(GetDbValue(db, keys.fontFace, "Friz Quadrata TT"), true)
    kit.outlineDropdown:SetValue(GetDbValue(db, keys.fontOutline, "OUTLINE"), true)
    kit.fontSizeSlider:SetMinMaxValues(fontSizeRange[1], fontSizeRange[2])
    kit.fontSizeSlider:SetValue(GetDbValue(db, keys.fontSize, 18), true)

    return card
end

---------------------------------------------------------------------------------
-- Legacy path: build a fresh card for the outlier shapes that the pool's
-- single-shape factory doesn't cover. Two known call sites:
--   - GUI-HealerMana.lua: fontSizes array (multiple slider rows)
--   - GUI-CombatTexts.lua: extraSlider (second slider next to font size)
-- Both are in modules whose GUI pages are navigated infrequently, so the
-- per-render cost matters less than for the DungeonTimers panel cards.
-- Build-fresh path matches the pre-refactor behavior bit for bit.
---------------------------------------------------------------------------------

local function CreateFontSettingsCardLegacy(scrollChild, yOffset, config)
    local title = config.title or "Font Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback
    local fontSizeRange = config.fontSizeRange or { 8, 72 }
    local fontSizes = config.fontSizes
    local searchable = config.searchable ~= false
    local includeSoftOutline = config.includeSoftOutline == true

    local keys = {
        fontFace = dbKeys.fontFace or "FontFace",
        fontSize = dbKeys.fontSize or "FontSize",
        fontOutline = dbKeys.fontOutline or "FontOutline",
    }

    local function getValue(key, default)
        return GetDbValue(db, key, default)
    end

    local function setValue(key, val)
        SetDbValue(db, key, val)
        if onChange then onChange() end
    end

    local widgets = {}
    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)

    local fontDropdown = GUIFrame:CreateDropdown(row1, "Font", {
        options = BuildFontList(),
        value = getValue(keys.fontFace, "Friz Quadrata TT"),
        callback = function(key) setValue(keys.fontFace, key) end,
        searchable = searchable,
        isFontPreview = true,
    })
    row1:AddWidget(fontDropdown, 0.5)
    table_insert(widgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row1, "Outline", {
        options = BuildOutlineOptions(includeSoftOutline),
        value = getValue(keys.fontOutline, "OUTLINE"),
        callback = function(key) setValue(keys.fontOutline, key) end,
    })
    row1:AddWidget(outlineDropdown, 0.5)
    table_insert(widgets, outlineDropdown)
    card:AddRow(row1, Theme.rowHeight)

    if fontSizes and #fontSizes > 0 then
        local maxPerRow = 2
        local lastBatchStart = math.floor((#fontSizes - 1) / maxPerRow) * maxPerRow + 1
        for i = 1, #fontSizes, maxPerRow do
            local isLast = i == lastBatchStart
            local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
            local row = GUIFrame:CreateRow(card.content, rowHeight)
            local countInRow = math.min(maxPerRow, #fontSizes - i + 1)
            local widthPct = 1 / countInRow
            for j = i, math.min(i + maxPerRow - 1, #fontSizes) do
                local sizeConfig = fontSizes[j]
                local sizeSlider = GUIFrame:CreateSlider(row, sizeConfig.label or "Size", {
                    min = fontSizeRange[1],
                    max = fontSizeRange[2],
                    step = 1,
                    value = getValue(sizeConfig.dbKey, 18),
                    callback = function(val) setValue(sizeConfig.dbKey, val) end,
                })
                row:AddWidget(sizeSlider, widthPct)
                table_insert(widgets, sizeSlider)
            end
            if isLast then
                card:AddRow(row, rowHeight, 0)
            else
                card:AddRow(row, rowHeight)
            end
        end
    else
        local extraSlider = config.extraSlider
        local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local fontSizeSlider = GUIFrame:CreateSlider(row2, "Font Size", {
            min = fontSizeRange[1],
            max = fontSizeRange[2],
            step = 1,
            value = getValue(keys.fontSize, 18),
            labelWidth = 60,
            callback = function(val) setValue(keys.fontSize, val) end,
        })
        row2:AddWidget(fontSizeSlider, extraSlider and 0.5 or 1)
        table_insert(widgets, fontSizeSlider)

        if extraSlider then
            local extra = GUIFrame:CreateSlider(row2, extraSlider.label or "Slider", {
                min = extraSlider.min or 0,
                max = extraSlider.max or 100,
                step = extraSlider.step or 1,
                value = getValue(extraSlider.dbKey, extraSlider.default or 0),
                labelWidth = extraSlider.labelWidth,
                callback = function(val) setValue(extraSlider.dbKey, val) end,
            })
            row2:AddWidget(extra, 0.5)
            table_insert(widgets, extra)
        end

        card:AddRow(row2, Theme.rowHeightLast, 0)
    end

    card.fontWidgets = widgets

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

        for _, widget in ipairs(self.fontWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            end
        end
    end

    return card, card:GetNextOffset(), widgets
end

---------------------------------------------------------------------------------
-- Public entry: CreateFontSettingsCard
--
-- Routes to the pool path for the simple shape (no fontSizes array, no
-- extraSlider) and to the legacy build-fresh path for the two outliers.
-- Signature unchanged from pre-pool: returns (card, nextOffset, widgets).
---------------------------------------------------------------------------------

function GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, config)
    config = config or {}

    -- Outlier shapes — legacy path. fontSizes (HealerMana) and extraSlider
    -- (CombatTexts) need shapes the single-shape factory doesn't cover. The
    -- pool's per-render cost matters less for these (page-navigation only)
    -- so building fresh is fine. searchable=false also routes here defensively
    -- — KEDropdown's searchable is set at construction with no setter, and
    -- the pooled factory builds with searchable=true. Currently no live
    -- caller passes false, but a future caller would get the correct
    -- non-searchable dropdown via this path.
    if (config.fontSizes and #config.fontSizes > 0)
        or config.extraSlider
        or config.searchable == false then
        return CreateFontSettingsCardLegacy(scrollChild, yOffset, config)
    end

    -- Pool path — covers the 25 simple-shape call sites.
    local kit = fontSettingsCardPool:Acquire(scrollChild)
    local card = ConfigureFontSettingsCardKit(kit, scrollChild, yOffset, config)
    return card, card:GetNextOffset(), card.fontWidgets
end
