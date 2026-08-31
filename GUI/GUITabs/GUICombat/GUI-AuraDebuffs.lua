-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraDebuffs.lua                                     ║
-- ║  GUI: Aura Debuffs                                       ║
-- ║  Purpose: Configuration panel for the AuraDebuffs        ║
-- ║           module (dispellable / important debuff icons). ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraDebuffs", true) end

GUIFrame:RegisterContent("AuraDebuffs", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraDebuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AD = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    -- Conditional group for BorderColorMode: the Custom Border Color picker
    -- (Visual Settings card) is only active when mode = "custom". The Dispel
    -- Type Colors card is always enabled because user color choices persist
    -- regardless of mode and take effect when "dispel" is active.
    manager:SetCondition("borderCustom", function() return db.BorderColorMode == "custom" end)

    -- "Reverse Cooldown Direction" only matters when Swipe is on, so it's
    -- greyed out when Swipe is unchecked.
    manager:SetCondition("swipeOn", function() return db.Swipe ~= false end)

    local function ApplySettings()
        if AD and AD.ApplySettings then AD:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraDebuffs", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraDebuffs")
        else
            KitnEssentials:DisableModule("AuraDebuffs")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Debuffs", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        ApplyModuleState(checked)
        KE:Print("Aura Debuffs: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType  = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint        = "AnchorFrom",
            anchorPoint      = "AnchorTo",
            xOffset          = "XOffset",
            yOffset          = "YOffset",
            strata           = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        onChangeCallback    = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display
    -- (Visibility card removed — module is filter-driven now: it shows
    -- whenever Enabled, and the Filters card decides which auras qualify.)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row4a, "Icon Size", {
        min = 16, max = 128, step = 1,
        value = db.IconSize or 32,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row4a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row4a, "Icon Spacing", {
        min = 0, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row4a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row4b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 8,
        callback = function(val) db.IconsPerRow = val; ApplySettings() end,
    })
    row4b:AddWidget(iconsPerRowSlider, 0.5)
    manager:Register(iconsPerRowSlider, "all")

    local maxRowsSlider = GUIFrame:CreateSlider(row4b, "Max Rows", {
        min = 1, max = 3, step = 1,
        value = db.MaxRows or 1,
        callback = function(val) db.MaxRows = val; ApplySettings() end,
    })
    row4b:AddWidget(maxRowsSlider, 0.5)
    manager:Register(maxRowsSlider, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    -- Separator between sliders and grow-direction dropdowns
    local row4sep1 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4a = GUIFrame:CreateSeparator(row4sep1)
    row4sep1:AddWidget(sep4a, 1)
    manager:Register(sep4a, "all")
    card4:AddRow(row4sep1, Theme.rowHeightSeparator)

    -- Icon Zoom removed: AuraDebuffs uses the KES standard icon crop via
    -- KE:ApplyIconZoom (0.3 / 7.5%) for visual consistency across modules.

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local growHorizDropdown = GUIFrame:CreateDropdown(row4c, "Grow Horizontal", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowHorizontal or "RIGHT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row4c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row4c, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "DOWN",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row4c:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    -- Separator between grow-direction dropdowns and swipe/reverse checkboxes
    local row4sep2 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4b = GUIFrame:CreateSeparator(row4sep2)
    row4sep2:AddWidget(sep4b, 1)
    manager:Register(sep4b, "all")
    card4:AddRow(row4sep2, Theme.rowHeightSeparator)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local swipeCheck = GUIFrame:CreateCheckbox(row4d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
            RefreshStates()  -- re-evaluate swipeOn condition for reverseCheck
        end,
    })
    row4d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local reverseCheck = GUIFrame:CreateCheckbox(row4d, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row4d:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "swipeOn")
    card4:AddRow(row4d, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Visual Settings
    -- 1x2 grid: BorderColorMode (left) + Custom Border Color (right).
    -- The custom color picker is greyed out when mode = "dispel" via the
    -- "borderCustom" conditional group.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Visual Settings", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local borderModeDropdown = GUIFrame:CreateDropdown(row5a, "Border Color Mode", {
        options = {
            { key = "dispel", text = "Dispel Type" },
            { key = "custom", text = "Custom Color" },
        },
        value = db.BorderColorMode or "dispel",
        callback = function(key)
            db.BorderColorMode = key
            -- Refresh the conditional groups so the custom color picker
            -- shows/greys out immediately.
            RefreshStates()
            ApplySettings()
        end,
    })
    row5a:AddWidget(borderModeDropdown, 0.5)
    manager:Register(borderModeDropdown, "all")

    local borderColorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Border Color", {
        color = db.BorderColor or { 0.8, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(borderColorPicker, 0.5)
    -- Only active when "custom" mode is selected.
    manager:Register(borderColorPicker, "borderCustom")
    card5:AddRow(row5a, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Dispel Type Colors (shared builder)
    --
    -- The per-type palette (db.DispelColors) card lives in a shared builder
    -- (GUI-DispelTypeColorsCard.lua); Aura Debuffs is its only consumer.
    -- Registered to "all" here, so it greys out with the Aura Debuffs
    -- master enable (unchanged behaviour).
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateDispelTypeColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        stateGroup = "all",
    })

    ----------------------------------------------------------------
    -- Card 7: Filtering Options
    --
    -- Each filter REMOVES matching auras from tracking when checked. The
    -- valid HARMFUL aura-filter tokens come from AuraUtil.AuraFilters
    -- (Blizzard_FrameXMLUtil/AuraUtil.lua); KE doesn't add any extras
    -- because the other tokens in that table are HELPFUL-only concepts.
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Filtering Options", yOffset)
    manager:Register(card7, "all")

    -- Intro "Filter Info" header
    local noteRow = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local filterNote = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Filter Info"),
        KE:ColorTextByTheme("-") .. " Each checked option hides additional matching debuffs.",
        Theme.rowHeight, "hide")
    noteRow:AddWidget(filterNote, 1)
    manager:Register(filterNote, "all")
    card7:AddRow(noteRow, Theme.rowHeight)

    -- Separator between the info note and the filter checkboxes.
    local filterSepRow = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local filterSep = GUIFrame:CreateSeparator(filterSepRow)
    filterSepRow:AddWidget(filterSep, 1)
    manager:Register(filterSep, "all")
    card7:AddRow(filterSepRow, Theme.rowHeightSeparator)

    -- Filter rows. Each entry: { key = Blizzard token, label = display label,
    -- tooltip = mouseover description }. RAID_IN_COMBAT omitted — it's a
    -- HELPFUL-side token (see the AuraDebuffs Filters defaults comment in
    -- Core/Defaults.lua).
    local FILTERS = {
        { key = "RAID",
          label   = "RAID",
          tooltip = "Filters out harmful auras your character can dispel." },
        { key = "CROWD_CONTROL",
          label   = "CROWD_CONTROL",
          tooltip = "Filters out auras with a crowd-control effect." },
        { key = "IMPORTANT",
          label   = "IMPORTANT",
          tooltip = "Filters out auras Blizzard flags as important." },
        { key = "RAID_PLAYER_DISPELLABLE",
          label   = "RAID_PLAYER_DISPELLABLE",
          tooltip = "Filters out harmful auras someone in your raid can dispel." },
        { key = "INCLUDE_NAME_PLATE_ONLY",
          label   = "INCLUDE_NAME_PLATE_ONLY",
          tooltip = "Filters out auras flagged to appear only on nameplates." },
    }

    local filters = db.Filters or {}
    local numFilters = #FILTERS
    local fIdx = 1
    while fIdx <= numFilters do
        local entryA = FILTERS[fIdx]
        local entryB = FILTERS[fIdx + 1]
        local isLastRow = (fIdx + 2 > numFilters)
        local rowH = isLastRow and Theme.rowHeightLast or Theme.rowHeight

        local filterRow = GUIFrame:CreateRow(card7.content, rowH)

        local checkA = GUIFrame:CreateCheckbox(filterRow, entryA.label, {
            value    = filters[entryA.key] == true,
            callback = function(checked) filters[entryA.key] = checked; ApplySettings() end,
            tooltip  = entryA.tooltip,
        })
        filterRow:AddWidget(checkA, 0.5)
        manager:Register(checkA, "all")

        if entryB then
            local checkB = GUIFrame:CreateCheckbox(filterRow, entryB.label, {
                value    = filters[entryB.key] == true,
                callback = function(checked) filters[entryB.key] = checked; ApplySettings() end,
                tooltip  = entryB.tooltip,
            })
            filterRow:AddWidget(checkB, 0.5)
            manager:Register(checkB, "all")
        end

        card7:AddRow(filterRow, rowH, isLastRow and 0 or nil)
        fIdx = fIdx + 2
    end

    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Blocklist
    --
    -- Per-entry editable list: Select Entry dropdown + Enabled toggle on
    -- one row, then a spell-icon + name preview with Spell ID and Label
    -- edit boxes, then Add New Entry / Delete Entry buttons. Default
    -- entries (entry.default == true) cannot be deleted.
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Blocklist", yOffset)
    manager:Register(card8, "all")

    db.Blocklist = db.Blocklist or {}

    -- The hardcoded blocklist is applied unconditionally regardless of a
    -- row's own enabled flag (see AuraRules.HARDCODED_BLOCKLIST_SET), so any
    -- row whose spell id is one of those ids can never actually be switched
    -- off -- whether it's a shipped default row or one the user typed in
    -- themselves. Read-only: this table is shared and used elsewhere as the
    -- returned exclude set.
    local ALWAYS_ON_BLOCKLIST_IDS = KE.AuraRules and KE.AuraRules.HARDCODED_BLOCKLIST_SET or {}

    local function IsAlwaysOnBlocklistEntry(spellId)
        return ALWAYS_ON_BLOCKLIST_IDS[spellId] == true
    end

    local selectedSpellId = nil
    local blocklistDropdown, spellIdInput, labelInput
    local spellIconFrame, spellIconTexture, spellNameLabel
    local enabledToggle, enabledAlwaysOnHint, deleteBtn

    -- Conditional group: Delete Entry button is only enabled when a
    -- non-default entry is selected. The master `db.Enabled` gate is
    -- handled by `manager:UpdateAll(mainEnabled)` BEFORE conditions run
    -- (see GUI-WidgetStateManager line 50), so the predicate only needs
    -- to check the per-selection condition.
    manager:SetCondition("deletable", function()
        if not selectedSpellId then return false end
        local entry = db.Blocklist[selectedSpellId]
        return not (type(entry) == "table" and entry.default)
    end)

    -- Conditional group: the Enabled toggle is disabled for an always-on
    -- entry -- flipping it off would be a lie, since the hardcoded filter
    -- keeps applying regardless.
    manager:SetCondition("toggleable", function()
        if not selectedSpellId then return true end
        return not IsAlwaysOnBlocklistEntry(selectedSpellId)
    end)

    local function GetSortedBlocklist()
        local sorted = {}
        for spellId, entry in pairs(db.Blocklist) do
            local label
            if type(entry) == "table" then
                label = entry.label or tostring(spellId)
            elseif type(entry) == "string" then
                label = entry
            else
                label = tostring(spellId)
            end
            table.insert(sorted, { spellId = spellId, label = label, entry = entry })
        end
        table.sort(sorted, function(a, b) return a.label < b.label end)
        return sorted
    end

    local function BuildDropdownOptions()
        local options = {}
        for spellId, entry in pairs(db.Blocklist) do
            local label
            if type(entry) == "table" then
                label = entry.label or tostring(spellId)
            elseif type(entry) == "string" then
                label = entry
            else
                label = tostring(spellId)
            end
            local isDisabled = type(entry) == "table" and not entry.enabled
                and not IsAlwaysOnBlocklistEntry(spellId)
            local text = label .. " (" .. spellId .. ")"
            if isDisabled then
                text = "|cff666666" .. text .. "|r"
            end
            options[tostring(spellId)] = text
        end
        return options
    end

    local function GetFirstSpellId()
        local sorted = GetSortedBlocklist()
        if #sorted > 0 then return sorted[1].spellId end
        return nil
    end

    local function UpdateSpellDisplay()
        if not selectedSpellId or not db.Blocklist[selectedSpellId] then
            spellIconFrame:Hide()
            spellNameLabel:SetText("")
            enabledAlwaysOnHint:Hide()
            return
        end

        spellIconFrame:Show()

        local entry = db.Blocklist[selectedSpellId]
        -- An always-on entry is filtered unconditionally, so it must always
        -- DISPLAY as on.
        local isEnabled = IsAlwaysOnBlocklistEntry(selectedSpellId)
            or (type(entry) == "table" and entry.enabled ~= false)
            or entry == true or type(entry) == "string"
        local label = type(entry) == "table" and entry.label
            or (type(entry) == "string" and entry or "")

        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(selectedSpellId)
        local spellName = spellInfo and spellInfo.name or "Unknown Spell"
        local spellIcon = spellInfo and spellInfo.iconID or 134400

        spellIconTexture:SetTexture(spellIcon)
        spellNameLabel:SetText(spellName)
        spellIdInput:SetValue(tostring(selectedSpellId), true)
        labelInput:SetValue(label, true)
        enabledToggle.toggle:SetValue(isEnabled, true)
        enabledAlwaysOnHint:SetShown(IsAlwaysOnBlocklistEntry(selectedSpellId))

        -- Re-run the manager so the "deletable" condition is re-evaluated
        -- against the new selection. Direct SetEnabled() would get clobbered
        -- by the outer RefreshStates() that fires at the end of the GUI
        -- builder (and again whenever the master Enable toggle flips).
        RefreshStates()
    end

    local function SelectSpell(spellId)
        selectedSpellId = spellId
        UpdateSpellDisplay()
    end

    -- Info "Blocklist Filter Info" header
    -- CreateText reserves ~23px for the title line (16pt + 2px spacer)
    -- before the body starts. This note runs ~265 characters at 12pt --
    -- three wrapped lines needing ~47px of body space. 23 + 47 = 70, plus
    -- a small buffer against font-metric rounding.
    local textRowSize = 76
    local infoRow = GUIFrame:CreateRow(card8.content, textRowSize)
    local infoText = GUIFrame:CreateText(infoRow,
        KE:ColorTextByTheme("Blocklist Filter Info"),
        KE:ColorTextByTheme("-") ..
            " Only possible to add auras that have been made non secret by Blizzard, for example all the Bloodlust ID's." ..
            " Adding a boss debuff's spell ID will not hide it -- filtering only works for spells Blizzard has made non-secret, so an unsupported ID silently does nothing.",
        textRowSize, "hide")
    infoRow:AddWidget(infoText, 1)
    manager:Register(infoText, "all")
    card8:AddRow(infoRow, textRowSize)

    -- Separator under the info note
    local sep1Row = GUIFrame:CreateRow(card8.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(sep1Row)
    sep1Row:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card8:AddRow(sep1Row, Theme.rowHeightSeparator)

    -- Row: Select Entry dropdown + Enabled toggle
    -- Inset 3px on each side so left/right edges line up with the separator's
    -- visible line (CreateSeparator anchors its line texture at LEFT+3 / RIGHT-3).
    -- First-cell pattern:  xOffset = 3, spacing = default + 3 (= 7)
    -- Last-cell pattern:   spacing = default - 1 (= 3, so right edge sits at W-3)
    local selectRow = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    blocklistDropdown = GUIFrame:CreateDropdown(selectRow, "Select Entry", {
        options = BuildDropdownOptions(),
        value   = tostring(GetFirstSpellId() or ""),
        callback = function(key)
            if key and key ~= "" then SelectSpell(tonumber(key)) end
        end,
    })
    selectRow:AddWidget(blocklistDropdown, 0.5, 7, 3)
    manager:Register(blocklistDropdown, "all")

    enabledToggle = GUIFrame:CreateCheckbox(selectRow, "Enabled", {
        value = true,
        callback = function(checked)
            if selectedSpellId and db.Blocklist[selectedSpellId] then
                local entry = db.Blocklist[selectedSpellId]
                if type(entry) == "table" then
                    entry.enabled = checked
                else
                    db.Blocklist[selectedSpellId] = {
                        label   = type(entry) == "string" and entry or nil,
                        enabled = checked,
                    }
                end
                blocklistDropdown:SetOptions(BuildDropdownOptions())
                blocklistDropdown:SetValue(tostring(selectedSpellId), true)
                ApplySettings()
            end
        end,
    })
    selectRow:AddWidget(enabledToggle, 0.5, 3)
    manager:Register(enabledToggle, "toggleable")

    -- Hover-only hint for an always-on entry. The toggle widget has no
    -- public API to change its tooltip after creation, so a thin mouse
    -- catcher sits over it instead, shown only while such an entry is
    -- selected -- SetEnabled(false) on the toggle already drops its own
    -- mouse handling, leaving this frame free to receive the hover.
    enabledAlwaysOnHint = CreateFrame("Frame", nil, enabledToggle.toggle)
    enabledAlwaysOnHint:SetAllPoints(enabledToggle.toggle)
    enabledAlwaysOnHint:SetFrameLevel(enabledToggle.toggle:GetFrameLevel() + 10)
    enabledAlwaysOnHint:EnableMouse(true)
    enabledAlwaysOnHint:Hide()
    enabledAlwaysOnHint:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 10, 10)
        GameTooltip:SetText(
            "Always filtered. This entry is applied unconditionally and cannot be turned off.",
            1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enabledAlwaysOnHint:SetScript("OnLeave", function() GameTooltip:Hide() end)

    card8:AddRow(selectRow, Theme.rowHeight)

    -- Separator under select/toggle row
    local sep2Row = GUIFrame:CreateRow(card8.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(sep2Row)
    sep2Row:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    card8:AddRow(sep2Row, Theme.rowHeightSeparator)

    -- Row: icon + name (0.5) + Spell ID input (0.25) + Label input (0.25)
    local detailRow = GUIFrame:CreateRow(card8.content, Theme.rowHeight)

    local spellInfoContainer = CreateFrame("Frame", nil, detailRow)
    spellInfoContainer:SetHeight(Theme.rowHeight)
    -- First-cell inset: xOffset=3, spacing=7 to align with separator's left edge.
    detailRow:AddWidget(spellInfoContainer, 0.5, 7, 3)

    spellIconFrame = CreateFrame("Frame", nil, spellInfoContainer)
    spellIconFrame:SetSize(34, 34)
    spellIconFrame:SetPoint("LEFT", spellInfoContainer, "LEFT", 0, 0)
    spellIconFrame:EnableMouse(true)

    spellIconTexture = spellIconFrame:CreateTexture(nil, "ARTWORK")
    spellIconTexture:SetPoint("TOPLEFT", 1, -1)
    spellIconTexture:SetPoint("BOTTOMRIGHT", -1, 1)
    spellIconTexture:SetTexture(134400)
    KE:ApplyIconZoom(spellIconTexture)
    -- Red border signals "blocklisted spell".
    KE:AddIconBorders(spellIconFrame, { 1, 0, 0, 1 })

    spellIconFrame:SetScript("OnEnter", function(self)
        if selectedSpellId then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 10, 10)
            GameTooltip:SetSpellByID(selectedSpellId)
            GameTooltip:Show()
        end
    end)
    spellIconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    spellNameLabel = spellInfoContainer:CreateFontString(nil, "OVERLAY")
    spellNameLabel:SetPoint("LEFT", spellIconFrame, "RIGHT", 6, 0)
    spellNameLabel:SetPoint("RIGHT", spellInfoContainer, "RIGHT", -4, 0)
    spellNameLabel:SetJustifyH("LEFT")
    KE:ApplyThemeFont(spellNameLabel, "normal")
    spellNameLabel:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    spellIdInput = GUIFrame:CreateEditBox(detailRow, "Spell ID", {
        value = "",
        callback = function(text)
            local newSpellId = tonumber(text)
            if newSpellId and selectedSpellId and newSpellId ~= selectedSpellId then
                local entry = db.Blocklist[selectedSpellId]
                if entry then
                    db.Blocklist[newSpellId] = entry
                    db.Blocklist[selectedSpellId] = nil
                    selectedSpellId = newSpellId
                    blocklistDropdown:SetOptions(BuildDropdownOptions())
                    blocklistDropdown:SetValue(tostring(newSpellId), true)
                    UpdateSpellDisplay()
                    ApplySettings()
                end
            end
        end,
    })
    detailRow:AddWidget(spellIdInput, 0.25)
    manager:Register(spellIdInput, "all")

    labelInput = GUIFrame:CreateEditBox(detailRow, "Label", {
        value = "",
        callback = function(text)
            if selectedSpellId and db.Blocklist[selectedSpellId] then
                local entry = db.Blocklist[selectedSpellId]
                if type(entry) == "table" then
                    entry.label = (text and text ~= "") and text or nil
                else
                    db.Blocklist[selectedSpellId] = {
                        label   = (text and text ~= "") and text or nil,
                        enabled = true,
                    }
                end
                blocklistDropdown:SetOptions(BuildDropdownOptions())
                blocklistDropdown:SetValue(tostring(selectedSpellId), true)
            end
        end,
    })
    -- Last-cell inset: spacing=3 so right edge sits at W-3 instead of W-default.
    detailRow:AddWidget(labelInput, 0.25, 3)
    manager:Register(labelInput, "all")
    card8:AddRow(detailRow, Theme.rowHeight)

    -- Separator under detail row
    local sep3Row = GUIFrame:CreateRow(card8.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(sep3Row)
    sep3Row:AddWidget(sep3, 1)
    manager:Register(sep3, "all")
    card8:AddRow(sep3Row, Theme.rowHeightSeparator)

    -- Row: Add New Entry + Delete Entry buttons. Uses a shorter row height
    -- to drop the unused gap below the buttons.
    local buttonRowH = Theme.rowHeightLast - 14
    local buttonRow = GUIFrame:CreateRow(card8.content, buttonRowH)
    local addBtn = GUIFrame:CreateButton(buttonRow, "Add New Entry", {
        height = 24,
        callback = function()
            local entryNum = 1
            local function labelExists(num)
                local testLabel = "Entry " .. num
                for _, entry in pairs(db.Blocklist) do
                    local lbl = (type(entry) == "table" and entry.label)
                        or (type(entry) == "string" and entry)
                    if lbl == testLabel then return true end
                end
                return false
            end
            while labelExists(entryNum) do entryNum = entryNum + 1 end

            local newLabel = "Entry " .. entryNum
            -- Reserve a sentinel negative spellId until the user supplies a real one
            local newSpellId = -1
            while db.Blocklist[newSpellId] do newSpellId = newSpellId - 1 end

            db.Blocklist[newSpellId] = { label = newLabel, enabled = true }

            blocklistDropdown:SetOptions(BuildDropdownOptions())
            blocklistDropdown:SetValue(tostring(newSpellId), true)
            SelectSpell(newSpellId)
            ApplySettings()
        end,
    })
    buttonRow:AddWidget(addBtn, 0.5, 7, 3)
    manager:Register(addBtn, "all")

    deleteBtn = GUIFrame:CreateButton(buttonRow, "Delete Entry", {
        height = 24,
        callback = function()
            if selectedSpellId and db.Blocklist[selectedSpellId] then
                local entry = db.Blocklist[selectedSpellId]
                if type(entry) == "table" and entry.default then return end
                db.Blocklist[selectedSpellId] = nil
                blocklistDropdown:SetOptions(BuildDropdownOptions())
                local nextSpell = GetFirstSpellId()
                if nextSpell then
                    blocklistDropdown:SetValue(tostring(nextSpell), true)
                    SelectSpell(nextSpell)
                else
                    selectedSpellId = nil
                    spellIdInput:SetValue("", true)
                    labelInput:SetValue("", true)
                    UpdateSpellDisplay()
                end
                ApplySettings()
            end
        end,
    })
    buttonRow:AddWidget(deleteBtn, 0.5, 3)
    manager:Register(deleteBtn, "deletable")
    card8:AddRow(buttonRow, buttonRowH, 0)

    -- Initial selection
    local firstSpell = GetFirstSpellId()
    if firstSpell then
        SelectSpell(firstSpell)
    else
        spellIconFrame:Hide()
    end

    yOffset = card8:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Font Settings
    ----------------------------------------------------------------
    local fontCard, _, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db    = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Count Size", dbKey = "FontSize",      default = 14 },
            { label = "Timer Size", dbKey = "TimerFontSize", default = 16 },
        },
        fontSizeRange      = { 8, 48 },
        onChangeCallback   = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end

    -- The card's own last row is added with no trailing gap, so re-open the
    -- spacing before appending to it.
    fontCard:AddSpacing(Theme.paddingSmall)

    local decimalRow = GUIFrame:CreateRow(fontCard.content, Theme.rowHeightLast)
    local decimalSlider = GUIFrame:CreateSlider(decimalRow, "Show Decimals Below (sec)", {
        min = 0, max = 10, step = 1,
        value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        callback = function(val) db.DecimalThreshold = val; ApplySettings() end,
    })
    decimalRow:AddWidget(decimalSlider, 0.5)
    manager:Register(decimalSlider, "all")
    fontCard:AddRow(decimalRow, Theme.rowHeightLast, 0)

    yOffset = fontCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 10: Element Positions
    --
    -- One anchor per element (Timer text / Stack text / Dispel icon)
    -- drives both AnchorFrom and AnchorTo — picking "CENTER" aligns the
    -- element's center with the button's center, picking "BOTTOMRIGHT"
    -- stacks them by bottom-right, etc.
    ----------------------------------------------------------------
    local card10 = GUIFrame:CreateCard(scrollChild, "Element Positions", yOffset)
    manager:Register(card10, "all")

    local TEXT_ANCHOR_OPTIONS = {
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

    db.TimerPosition  = db.TimerPosition or {}
    db.StackPosition  = db.StackPosition
        or { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = 0, YOffset = 2 }
    db.DispelPosition = db.DispelPosition
        or { AnchorFrom = "TOPRIGHT", AnchorTo = "TOPRIGHT", XOffset = 0, YOffset = 0 }
    local tp, sp, dp = db.TimerPosition, db.StackPosition, db.DispelPosition

    -- Row: Timer Anchor + Timer X + Timer Y (each 1/3 width)
    local row10a = GUIFrame:CreateRow(card10.content, Theme.rowHeight)
    local timerAnchor = GUIFrame:CreateDropdown(row10a, "Timer Text Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = tp.AnchorFrom or "CENTER",
        callback = function(key)
            tp.AnchorFrom = key
            tp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row10a:AddWidget(timerAnchor, 1 / 3)
    manager:Register(timerAnchor, "all")

    local timerX = GUIFrame:CreateSlider(row10a, "Timer X", {
        min = -50, max = 50, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) tp.XOffset = val; ApplySettings() end,
    })
    row10a:AddWidget(timerX, 1 / 3)
    manager:Register(timerX, "all")

    local timerY = GUIFrame:CreateSlider(row10a, "Timer Y", {
        min = -50, max = 50, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) tp.YOffset = val; ApplySettings() end,
    })
    row10a:AddWidget(timerY, 1 / 3)
    manager:Register(timerY, "all")
    card10:AddRow(row10a, Theme.rowHeight)

    -- Separator
    local row10sep = GUIFrame:CreateRow(card10.content, Theme.rowHeightSeparator)
    local sep10 = GUIFrame:CreateSeparator(row10sep)
    row10sep:AddWidget(sep10, 1)
    manager:Register(sep10, "all")
    card10:AddRow(row10sep, Theme.rowHeightSeparator)

    -- Row: Stack Anchor + Stack X + Stack Y (each 1/3 width)
    local row10b = GUIFrame:CreateRow(card10.content, Theme.rowHeight)
    local stackAnchor = GUIFrame:CreateDropdown(row10b, "Debuff Stacks Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = sp.AnchorFrom or "BOTTOMRIGHT",
        callback = function(key)
            sp.AnchorFrom = key
            sp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row10b:AddWidget(stackAnchor, 1 / 3)
    manager:Register(stackAnchor, "all")

    local stackX = GUIFrame:CreateSlider(row10b, "Stack X", {
        min = -50, max = 50, step = 1,
        value = sp.XOffset or 0,
        callback = function(val) sp.XOffset = val; ApplySettings() end,
    })
    row10b:AddWidget(stackX, 1 / 3)
    manager:Register(stackX, "all")

    local stackY = GUIFrame:CreateSlider(row10b, "Stack Y", {
        min = -50, max = 50, step = 1,
        value = sp.YOffset or 2,
        callback = function(val) sp.YOffset = val; ApplySettings() end,
    })
    row10b:AddWidget(stackY, 1 / 3)
    manager:Register(stackY, "all")
    card10:AddRow(row10b, Theme.rowHeight)

    -- Separator
    local row10sep2 = GUIFrame:CreateRow(card10.content, Theme.rowHeightSeparator)
    local sep10b = GUIFrame:CreateSeparator(row10sep2)
    row10sep2:AddWidget(sep10b, 1)
    manager:Register(sep10b, "all")
    card10:AddRow(row10sep2, Theme.rowHeightSeparator)

    -- Row: Dispel Icon Anchor + Dispel X + Dispel Y (each 1/3 width)
    local row10c = GUIFrame:CreateRow(card10.content, Theme.rowHeightLast)
    local dispelAnchor = GUIFrame:CreateDropdown(row10c, "Dispel Type Icon Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = dp.AnchorFrom or "TOPRIGHT",
        callback = function(key)
            dp.AnchorFrom = key
            dp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row10c:AddWidget(dispelAnchor, 1 / 3)
    manager:Register(dispelAnchor, "all")

    local dispelX = GUIFrame:CreateSlider(row10c, "Dispel X", {
        min = -50, max = 50, step = 1,
        value = dp.XOffset or 0,
        callback = function(val) dp.XOffset = val; ApplySettings() end,
    })
    row10c:AddWidget(dispelX, 1 / 3)
    manager:Register(dispelX, "all")

    local dispelY = GUIFrame:CreateSlider(row10c, "Dispel Y", {
        min = -50, max = 50, step = 1,
        value = dp.YOffset or 0,
        callback = function(val) dp.YOffset = val; ApplySettings() end,
    })
    row10c:AddWidget(dispelY, 1 / 3)
    manager:Register(dispelY, "all")
    card10:AddRow(row10c, Theme.rowHeightLast, 0)

    yOffset = card10:GetNextOffset()

    RefreshStates()
    return yOffset
end)
