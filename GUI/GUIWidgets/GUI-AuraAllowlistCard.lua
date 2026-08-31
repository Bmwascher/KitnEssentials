---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local ICON_ESCAPE = "|T%d:16:16:0:0:64:64:5:59:5:59|t "

----------------------------------------------------------------
-- Allowlist
--
-- Per-entry editable list: Select Entry dropdown + Enabled toggle on
-- one row, then a spell-icon + name preview with Spell ID and Label
-- edit boxes, then Add New Entry / Delete Entry buttons. Default
-- entries (entry.default == true) cannot be deleted.
----------------------------------------------------------------
function GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, config)
    config = config or {}
    assert(type(config.allowlist) == "table", "CreateAuraAllowlistCard requires an allowlist table")
    assert(type(config.getDefaults) == "function", "CreateAuraAllowlistCard requires getDefaults")
    assert(type(config.restoreActions) == "table" and #config.restoreActions > 0,
        "CreateAuraAllowlistCard requires restore actions")

    local allowlist = config.allowlist
    local drafts = {}

    local function GetEntry(spellID)
        return drafts[spellID] or allowlist[spellID]
    end

    local function IsDraft(spellID)
        return drafts[spellID] ~= nil
    end

    local function BuildValidationMap()
        local entries = {}
        for spellID, entry in pairs(allowlist) do entries[spellID] = entry end
        for spellID, entry in pairs(drafts) do entries[spellID] = entry end
        return entries
    end

    local function LabelExists(label)
        local sets = { allowlist, drafts }
        for i = 1, #sets do
            for _, entry in pairs(sets[i]) do
                local stored = (type(entry) == "table" and entry.label)
                    or (type(entry) == "string" and entry)
                if stored == label then return true end
            end
        end
        return false
    end

    local function AllocateDraftID()
        local spellID = -1
        while allowlist[spellID] ~= nil or drafts[spellID] ~= nil do
            spellID = spellID - 1
        end
        return spellID
    end

    local function ResolveLabel(spellID, entry)
        if type(entry) == "table" and entry.label and entry.label ~= "" then
            return entry.label
        end
        if type(entry) == "string" and entry ~= "" then
            return entry
        end

        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        return (info and info.name) or "Unknown Spell"
    end

    local card = GUIFrame:CreateCard(scrollChild, config.title, yOffset)
    local innerManager = GUIFrame:CreateWidgetStateManager()

    local selectedSpellId = nil
    local allowlistDropdown, spellIdInput, labelInput
    local spellIconFrame, spellIconTexture, spellNameLabel
    local enabledToggle, deleteBtn

    -- Conditional group: Delete Entry button is only enabled when a
    -- non-default entry is selected. The master enable gate is handled by
    -- card:SetEnabled below, so the predicate only needs to check the
    -- per-selection condition.
    innerManager:SetCondition("deletable", function()
        if not selectedSpellId then return false end
        local entry = GetEntry(selectedSpellId)
        return not (type(entry) == "table" and entry.default)
    end)

    -- Conditional group: the Spell ID box is disabled for a shipped row --
    -- re-keying it would carry its `default` flag onto an unshipped id,
    -- which is a permanently undeletable row (see CanRekeyAllowlistEntry).
    innerManager:SetCondition("editableId", function()
        if not selectedSpellId then return false end
        local entry = GetEntry(selectedSpellId)
        return not (type(entry) == "table" and entry.default)
    end)

    local function GetSortedAllowlist()
        local sorted = {}
        local function CollectRows(source)
            for spellId, entry in pairs(source) do
                table.insert(sorted, { spellId = spellId, label = ResolveLabel(spellId, entry), entry = entry })
            end
        end
        CollectRows(allowlist)
        CollectRows(drafts)
        -- Tie-broken on the id: many names ship under more than one id, and
        -- comparing labels alone leaves their order to whatever `pairs`
        -- happened to yield, so the list would reshuffle between rebuilds.
        table.sort(sorted, function(a, b)
            if a.label == b.label then return a.spellId < b.spellId end
            return a.label < b.label
        end)
        return sorted
    end

    -- The dropdown widget has no icon slot, so the icon rides in the option
    -- text as an inline texture escape. 5 and 59 on a 64-texel sheet is the
    -- same crop KE:ApplyIconZoom applies at its default zoom, so a list row
    -- matches the preview icon under it.

    -- ORDERED array form, not a key/value map: the widget sorts a map by key,
    -- which on this card means by spell id rendered as a string.
    local function BuildDropdownOptions()
        local options = {}
        local sorted = GetSortedAllowlist()

        for i = 1, #sorted do
            local spellId, entry, label = sorted[i].spellId, sorted[i].entry, sorted[i].label
            -- `== false`, not `not entry.enabled`: the filter rule treats a row
            -- with no enabled key as ENABLED, and a spec pins that. Greying it
            -- here would show a row as off while its spell still gets through.
            local isDisabled = type(entry) == "table" and entry.enabled == false
            local text = label .. " (" .. spellId .. ")"
            if isDisabled then
                text = "|cff666666" .. text .. "|r"
            end
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
            options[i] = {
                value = tostring(spellId),
                text  = ICON_ESCAPE:format(info and info.iconID or 134400) .. text,
            }
        end

        return options
    end

    local function GetFirstSpellId()
        local sorted = GetSortedAllowlist()
        if #sorted > 0 then return sorted[1].spellId end
        return nil
    end

    local cardEnabled = true
    local baseSetEnabled = card.SetEnabled

    local function RefreshChildStates()
        innerManager:UpdateAll(cardEnabled)
    end

    function card:SetEnabled(enabled)
        cardEnabled = enabled and true or false
        if baseSetEnabled then baseSetEnabled(self, cardEnabled) end
        innerManager:UpdateAll(cardEnabled)
    end

    local function UpdateSpellDisplay()
        if not selectedSpellId or not GetEntry(selectedSpellId) then
            spellIconFrame:Hide()
            spellNameLabel:SetText("")
            return
        end

        spellIconFrame:Show()

        local entry = GetEntry(selectedSpellId)
        local isEnabled = (type(entry) == "table" and entry.enabled ~= false)
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

        -- Re-run the manager so the "deletable" and "editableId" conditions
        -- are re-evaluated against the new selection. Direct SetEnabled()
        -- would get clobbered by the outer UpdateAll() that fires whenever
        -- the page's master Enable toggle flips, which reaches this card
        -- through card:SetEnabled above.
        RefreshChildStates()
    end

    local function SelectSpell(spellID, notify)
        local changed = selectedSpellId ~= spellID
        selectedSpellId = spellID
        UpdateSpellDisplay()
        if changed and notify and config.onSelectionChanged then
            config.onSelectionChanged(spellID)
        end
    end

    -- The restore buttons replace the whole table, so they need one call that
    -- rebuilds the dropdown and re-selects something valid. Selection is not
    -- preserved across a restore: the previously selected row may no longer
    -- exist.
    local function RefreshAllowlist(notify)
        allowlistDropdown:SetOptions(BuildDropdownOptions())
        local first = GetFirstSpellId()
        if first then
            allowlistDropdown:SetValue(tostring(first), true)
            SelectSpell(first, notify)
        else
            -- Same clearing the original's delete path does: without these the
            -- boxes keep the text of a row that is no longer selected.
            selectedSpellId = nil
            spellIdInput:SetValue("", true)
            labelInput:SetValue("", true)
            UpdateSpellDisplay()
        end
    end

    -- CreateText reserves ~23px for the title line (16pt + 2px spacer)
    -- before the body starts. This note runs ~200 characters at 12pt --
    -- three wrapped lines needing ~47px of body space. 23 + 47 = 70, plus
    -- a small buffer against font-metric rounding.
    local textRowSize = 76
    local infoRow = GUIFrame:CreateRow(card.content, textRowSize)
    local infoText = GUIFrame:CreateText(infoRow,
        KE:ColorTextByTheme(config.infoTitle or ""),
        KE:ColorTextByTheme("-") .. " " .. config.infoText,
        textRowSize, "hide")
    infoRow:AddWidget(infoText, 1)
    innerManager:Register(infoText, "all")
    card:AddRow(infoRow, textRowSize)

    local restoreRowH = Theme.rowHeightLast - 10
    local restoreRow = GUIFrame:CreateRow(card.content, restoreRowH)

    local restoreCount = #config.restoreActions
    for i = 1, restoreCount do
        local action = config.restoreActions[i]
        local isFirst = (i == 1)
        local isLast = (i == restoreCount)
        local restoreBtn = GUIFrame:CreateButton(restoreRow, action.label, {
            tooltip = action.tooltip,
            height = 28,
            callback = function()
                drafts = {}
                KE.AuraRules.RestoreAllowlistDefaults(
                    allowlist,
                    config.getDefaults(),
                    action.resolveEnabled
                )
                RefreshAllowlist(false)
                if config.onChangeCallback then config.onChangeCallback() end
            end,
        })
        restoreRow:AddWidget(restoreBtn, 1 / restoreCount, isLast and 3 or 7, isFirst and 3 or nil)
        innerManager:Register(restoreBtn, "all")
    end

    card:AddRow(restoreRow, restoreRowH)

    -- Separator under the restore buttons
    local sep1Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(sep1Row)
    sep1Row:AddWidget(sep1, 1)
    innerManager:Register(sep1, "all")
    card:AddRow(sep1Row, Theme.rowHeightSeparator)

    -- Row: Select Entry dropdown + Enabled toggle
    -- Inset 3px on each side so left/right edges line up with the separator's
    -- visible line (CreateSeparator anchors its line texture at LEFT+3 / RIGHT-3).
    -- First-cell pattern:  xOffset = 3, spacing = default + 3 (= 7)
    -- Last-cell pattern:   spacing = default - 1 (= 3, so right edge sits at W-3)
    local selectRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    allowlistDropdown = GUIFrame:CreateDropdown(selectRow, "Select Entry", {
        options = BuildDropdownOptions(),
        value   = tostring(GetFirstSpellId() or ""),
        callback = function(key)
            if key and key ~= "" then SelectSpell(tonumber(key), true) end
        end,
    })
    selectRow:AddWidget(allowlistDropdown, 0.5, 7, 3)
    innerManager:Register(allowlistDropdown, "all")

    enabledToggle = GUIFrame:CreateCheckbox(selectRow, "Enabled", {
        value = true,
        callback = function(checked)
            if selectedSpellId and GetEntry(selectedSpellId) then
                local entry = GetEntry(selectedSpellId)
                local isCommitted = not IsDraft(selectedSpellId)
                local target = isCommitted and allowlist or drafts
                if type(entry) == "table" then
                    entry.enabled = checked
                else
                    target[selectedSpellId] = {
                        label   = type(entry) == "string" and entry or nil,
                        enabled = checked,
                    }
                end
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                allowlistDropdown:SetValue(tostring(selectedSpellId), true)
                if isCommitted and config.onChangeCallback then
                    config.onChangeCallback()
                end
            end
        end,
    })
    selectRow:AddWidget(enabledToggle, 0.5, 3)
    innerManager:Register(enabledToggle, "all")

    card:AddRow(selectRow, Theme.rowHeight)

    -- Separator under select/toggle row
    local sep2Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(sep2Row)
    sep2Row:AddWidget(sep2, 1)
    innerManager:Register(sep2, "all")
    card:AddRow(sep2Row, Theme.rowHeightSeparator)

    -- Row: icon + name (0.5) + Spell ID input (0.25) + Label input (0.25)
    local detailRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)

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
    KE:AddIconBorders(spellIconFrame)

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
            if KE.AuraRules.CanRekeyAllowlistEntry(BuildValidationMap(), selectedSpellId, newSpellId) then
                local entry = GetEntry(selectedSpellId)
                if IsDraft(selectedSpellId) then
                    drafts[selectedSpellId] = nil
                else
                    allowlist[selectedSpellId] = nil
                end
                allowlist[newSpellId] = entry
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                allowlistDropdown:SetValue(tostring(newSpellId), true)
                SelectSpell(newSpellId, true)
                if config.onChangeCallback then config.onChangeCallback() end
            else
                -- Every refusal lands here, blank and non-numeric input
                -- included: the box keeps whatever was typed, so without this
                -- it would show a value that was never stored. With no row
                -- selected there is nothing to restore, hence the empty string.
                spellIdInput:SetValue(selectedSpellId and tostring(selectedSpellId) or "", true)
            end
        end,
    })
    detailRow:AddWidget(spellIdInput, 0.25)
    innerManager:Register(spellIdInput, "editableId")

    labelInput = GUIFrame:CreateEditBox(detailRow, "Label", {
        value = "",
        callback = function(text)
            if selectedSpellId and GetEntry(selectedSpellId) then
                local entry = GetEntry(selectedSpellId)
                local target = IsDraft(selectedSpellId) and drafts or allowlist
                if type(entry) == "table" then
                    entry.label = (text and text ~= "") and text or nil
                else
                    target[selectedSpellId] = {
                        label   = (text and text ~= "") and text or nil,
                        enabled = true,
                    }
                end
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                allowlistDropdown:SetValue(tostring(selectedSpellId), true)
            end
        end,
    })
    -- Last-cell inset: spacing=3 so right edge sits at W-3 instead of W-default.
    detailRow:AddWidget(labelInput, 0.25, 3)
    innerManager:Register(labelInput, "all")
    card:AddRow(detailRow, Theme.rowHeight)

    -- Separator under detail row
    local sep3Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(sep3Row)
    sep3Row:AddWidget(sep3, 1)
    innerManager:Register(sep3, "all")
    card:AddRow(sep3Row, Theme.rowHeightSeparator)

    -- Row: Add New Entry + Delete Entry buttons. Uses a shorter row height
    -- to drop the unused gap below the buttons.
    local buttonRowH = Theme.rowHeightLast - 14
    local buttonRow = GUIFrame:CreateRow(card.content, buttonRowH)
    local addBtn = GUIFrame:CreateButton(buttonRow, "Add New Entry", {
        height = 24,
        callback = function()
            local entryNum = 1
            while LabelExists("Entry " .. entryNum) do entryNum = entryNum + 1 end
            local newLabel = "Entry " .. entryNum

            local newSpellId = AllocateDraftID()
            drafts[newSpellId] = { label = newLabel, enabled = true }

            allowlistDropdown:SetOptions(BuildDropdownOptions())
            allowlistDropdown:SetValue(tostring(newSpellId), true)
            SelectSpell(newSpellId, true)
        end,
    })
    buttonRow:AddWidget(addBtn, 0.5, 7, 3)
    innerManager:Register(addBtn, "all")

    deleteBtn = GUIFrame:CreateButton(buttonRow, "Delete Entry", {
        height = 24,
        callback = function()
            if selectedSpellId and GetEntry(selectedSpellId) then
                local entry = GetEntry(selectedSpellId)
                if type(entry) == "table" and entry.default then return end
                local wasCommitted = not IsDraft(selectedSpellId)
                if wasCommitted then
                    allowlist[selectedSpellId] = nil
                else
                    drafts[selectedSpellId] = nil
                end
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                local nextSpell = GetFirstSpellId()
                if nextSpell then
                    allowlistDropdown:SetValue(tostring(nextSpell), true)
                    SelectSpell(nextSpell, true)
                else
                    selectedSpellId = nil
                    spellIdInput:SetValue("", true)
                    labelInput:SetValue("", true)
                    UpdateSpellDisplay()
                end
                if wasCommitted and config.onChangeCallback then
                    config.onChangeCallback()
                end
            end
        end,
    })
    buttonRow:AddWidget(deleteBtn, 0.5, 3)
    innerManager:Register(deleteBtn, "deletable")
    card:AddRow(buttonRow, buttonRowH, 0)

    -- Initial selection
    local firstSpell = GetFirstSpellId()
    if firstSpell then
        SelectSpell(firstSpell, false)
    else
        spellIconFrame:Hide()
    end

    return card, card:GetNextOffset()
end
