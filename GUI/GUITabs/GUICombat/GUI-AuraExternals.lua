-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraExternals.lua                                   ║
-- ║  GUI: Aura Externals                                     ║
-- ║  Purpose: Configuration panel for the AuraExternals      ║
-- ║           module (external defensives display).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local PlaySoundFile = PlaySoundFile

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraExternals", true) end

GUIFrame:RegisterContent("AuraExternals", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraExternals
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AX = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AX and AX.ApplySettings then AX:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraExternals", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraExternals")
        else
            KitnEssentials:DisableModule("AuraExternals")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- "Reverse Cooldown Direction" only matters when Swipe is on, so it's
    -- greyed out when Swipe is unchecked.
    manager:SetCondition("swipeOn", function() return db.Swipe ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Externals", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        ApplyModuleState(checked)
        KE:Print("Aura Externals: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    local cardTracked = GUIFrame:CreateCard(scrollChild, "Tracked Auras", yOffset)
    manager:Register(cardTracked, "all")

    local row1b = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightLast)
    local defensivesCheck = GUIFrame:CreateCheckbox(row1b, "Include Defensives", {
        value = db.ShowBigDefensives ~= false,
        callback = function(checked) db.ShowBigDefensives = checked; ApplySettings() end,
        tooltip = "Include your own large defensive cooldowns (Shield Wall, Iron Bark, etc.) alongside externally-applied defensives.",
    })
    row1b:AddWidget(defensivesCheck, 1)
    manager:Register(defensivesCheck, "all")
    cardTracked:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = cardTracked:GetNextOffset()

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
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 36,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3a, "Icon Spacing", {
        min = 0, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row3a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row3b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 6,
        callback = function(val) db.IconsPerRow = val; ApplySettings() end,
    })
    row3b:AddWidget(iconsPerRowSlider, 0.5)
    manager:Register(iconsPerRowSlider, "all")

    local maxRowsSlider = GUIFrame:CreateSlider(row3b, "Max Rows", {
        min = 1, max = 3, step = 1,
        value = db.MaxRows or 1,
        callback = function(val) db.MaxRows = val; ApplySettings() end,
    })
    row3b:AddWidget(maxRowsSlider, 0.5)
    manager:Register(maxRowsSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    -- Separator between sliders and grow-direction dropdowns
    local row3sep1 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3a = GUIFrame:CreateSeparator(row3sep1)
    row3sep1:AddWidget(sep3a, 1)
    manager:Register(sep3a, "all")
    card3:AddRow(row3sep1, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local growHorizDropdown = GUIFrame:CreateDropdown(row3c, "Grow Horizontal", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowHorizontal or "RIGHT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row3c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row3c, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "DOWN",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row3c:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeight)

    -- Separator between grow-direction dropdowns and swipe/reverse checkboxes
    local row3sep2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3b = GUIFrame:CreateSeparator(row3sep2)
    row3sep2:AddWidget(sep3b, 1)
    manager:Register(sep3b, "all")
    card3:AddRow(row3sep2, Theme.rowHeightSeparator)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local swipeCheck = GUIFrame:CreateCheckbox(row3d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
            RefreshStates()  -- re-evaluate swipeOn condition for reverseCheck
        end,
    })
    row3d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local reverseCheck = GUIFrame:CreateCheckbox(row3d, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row3d:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "swipeOn")
    card3:AddRow(row3d, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset, glowWidgets = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow Settings",
        db = db,
        dbKeys = {
            enabled   = "GlowEnabled",
            type      = "GlowType",
            color     = "GlowColor",
            lines     = "GlowLines",
            frequency = "GlowFrequency",
            length    = "GlowLength",
            thickness = "GlowThickness",
            border    = "GlowBorder",
            scale     = "GlowScale",
            startAnim = "GlowStartAnim",
            duration  = "GlowDuration",
        },
        types = {
            { key = "pixel",    text = "Pixel" },
            { key = "ants",     text = "Ants" },
            { key = "procloop", text = "Proc Loop" },
            { key = "alert",    text = "Alert" },
        },
        resolveType = KE.AuraGlowRules.ResolveType,
        -- Pixel is now a real resolved type, so the card's default lookup
        -- would show its Length and Border controls too. This display's
        -- border is animation-driven and honours neither, so the override
        -- maps `pixel` to the two rows it does honour and omits every other
        -- group -- which is also what keeps the retired autocast and proc
        -- geometry rows hidden.
        -- Every group must stay REACHABLE by the visibility loop, including the
        -- ones that must never show: the loop is what calls SetShown(false),
        -- so a group left out of this table is a group nothing ever hides.
        -- Length and Border therefore move to a key no resolved type equals,
        -- rather than being dropped.
        typeRows = function(rows)
            return {
                pixel       = rows.pixel,
                unsupported = rows.pixelExtras,
                autocast    = rows.autocast,
                proc        = rows.proc,
            }
        end,
        showSpeed = function() return true end,
        speedAdapter = {
            -- WRAPPED, not passed bare. The read rule's result needs
            -- normalising -- nil or zero becomes 0.25, then clamp -- and the
            -- glow card is shared and generic, so it has no access to these
            -- rules. Passing ReadSpeed directly hands the slider a nil on a
            -- profile with no stored frequency.
            read = function(readDb, readKeys)
                return KE.AuraGlowRules.NormaliseFrequency(
                    KE.AuraGlowRules.ReadSpeed(readDb, readKeys), 0.05, 2)
            end,
            write   = KE.AuraGlowRules.WriteSpeed,
            setType = KE.AuraGlowRules.SetType,
            min     = 0.05,
            max     = 2, -- keeps the old 0.5s proc period reachable
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    if glowWidgets then
        manager:RegisterGroup(glowWidgets, "all")
    end
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 5: Sound (Seven Tracked Externals)
    --
    -- Plays the configured sound when one of a fixed list of seven
    -- external-defensive spells lands on you -- Blizzard's sound-trigger
    -- API takes a spell ID, not a filter, so this can't cover every
    -- external defensive. Self-applied big defensives are silent.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Sound (Seven Tracked Externals)", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local soundEnabledCheck = GUIFrame:CreateCheckbox(row5a, "Enable Sound", {
        value = db.SoundEnabled ~= false,
        callback = function(checked) db.SoundEnabled = checked; ApplySettings() end,
    })
    row5a:AddWidget(soundEnabledCheck, 1)
    manager:Register(soundEnabledCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    -- Separator between Enable toggle and the sound dropdown/test row
    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sep5, 1)
    manager:Register(sep5, "all")
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do
            soundList[name] = name
        end
    end
    soundList["None"] = "None"

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row5b, "On Application Sound", {
        options = soundList,
        value = db.SoundName or "None",
        searchable = true,
        callback = function(key) db.SoundName = key; ApplySettings() end,
    })
    row5b:AddWidget(soundDropdown, 0.5)
    manager:Register(soundDropdown, "all")

    -- Test button: plays whatever sound is currently selected. y=-12 places
    -- the 28px button center on the dropdown bar center (matches the pattern
    -- used in DungeonTimers detail panel).
    local soundTestBtn = GUIFrame:CreateButton(row5b, "Test", {
        height = 28,
        callback = function()
            local name = db.SoundName
            if not name or name == "None" or not LSM then return end
            local soundPath = LSM:Fetch("sound", name)
            if soundPath then PlaySoundFile(soundPath) end
        end,
    })
    row5b:AddWidget(soundTestBtn, 0.5, nil, 0, -12)
    manager:Register(soundTestBtn, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Allowlist
    --
    -- Per-entry editable list: Select Entry dropdown + Enabled toggle on
    -- one row, then a spell-icon + name preview with Spell ID and Label
    -- edit boxes, then Add New Entry / Delete Entry buttons. Default
    -- entries (entry.default == true) cannot be deleted.
    ----------------------------------------------------------------
    local card = GUIFrame:CreateCard(scrollChild, "Allowlist", yOffset)
    manager:Register(card, "all")

    -- The shipped rows, read from the defaults rather than duplicated here.
    -- A second copy would drift the first time the seed changed.
    local function ShippedAllowlist()
        if not KE.GetDefaultDB then return {} end
        local root = KE:GetDefaultDB()
        local section = root and root.profile and root.profile.AuraExternals
        return (section and section.Allowlist) or {}
    end

    db.Allowlist = db.Allowlist or {}

    local selectedSpellId = nil
    local allowlistDropdown, spellIdInput, labelInput
    local spellIconFrame, spellIconTexture, spellNameLabel
    local enabledToggle, deleteBtn

    -- Conditional group: Delete Entry button is only enabled when a
    -- non-default entry is selected. The master `db.Enabled` gate is
    -- handled by `manager:UpdateAll(mainEnabled)` BEFORE conditions run
    -- (GUI-WidgetStateManager), so the predicate only needs to check the
    -- per-selection condition.
    manager:SetCondition("deletable", function()
        if not selectedSpellId then return false end
        local entry = db.Allowlist[selectedSpellId]
        return not (type(entry) == "table" and entry.default)
    end)

    -- Conditional group: the Spell ID box is disabled for a shipped row --
    -- re-keying it would carry its `default` flag onto an unshipped id,
    -- which is a permanently undeletable row (see CanRekeyAllowlistEntry).
    manager:SetCondition("editableId", function()
        if not selectedSpellId then return false end
        local entry = db.Allowlist[selectedSpellId]
        return not (type(entry) == "table" and entry.default)
    end)

    local function GetSortedAllowlist()
        local sorted = {}
        for spellId, entry in pairs(db.Allowlist) do
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
        for spellId, entry in pairs(db.Allowlist) do
            local label
            if type(entry) == "table" then
                label = entry.label or tostring(spellId)
            elseif type(entry) == "string" then
                label = entry
            else
                label = tostring(spellId)
            end
            -- `== false`, not `not entry.enabled`: the filter rule treats a row
            -- with no enabled key as ENABLED, and a spec pins that. Greying it
            -- here would show a row as off while its spell still gets through.
            local isDisabled = type(entry) == "table" and entry.enabled == false
            local text = label .. " (" .. spellId .. ")"
            if isDisabled then
                text = "|cff666666" .. text .. "|r"
            end
            options[tostring(spellId)] = text
        end
        return options
    end

    local function GetFirstSpellId()
        local sorted = GetSortedAllowlist()
        if #sorted > 0 then return sorted[1].spellId end
        return nil
    end

    local function UpdateSpellDisplay()
        if not selectedSpellId or not db.Allowlist[selectedSpellId] then
            spellIconFrame:Hide()
            spellNameLabel:SetText("")
            return
        end

        spellIconFrame:Show()

        local entry = db.Allowlist[selectedSpellId]
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
        -- would get clobbered by the outer RefreshStates() that fires at
        -- the end of the GUI builder (and again whenever the master Enable
        -- toggle flips).
        RefreshStates()
    end

    local function SelectSpell(spellId)
        selectedSpellId = spellId
        UpdateSpellDisplay()
    end

    -- The restore buttons replace the whole table, so they need one call that
    -- rebuilds the dropdown and re-selects something valid. Selection is not
    -- preserved across a restore: the previously selected row may no longer
    -- exist.
    local function RefreshAllowlist()
        allowlistDropdown:SetOptions(BuildDropdownOptions())
        local first = GetFirstSpellId()
        if first then
            allowlistDropdown:SetValue(tostring(first), true)
            SelectSpell(first)
        else
            -- Same clearing the original's delete path does: without these the
            -- boxes keep the text of a row that is no longer selected.
            selectedSpellId = nil
            spellIdInput:SetValue("", true)
            labelInput:SetValue("", true)
            UpdateSpellDisplay()
        end
        ApplySettings()
    end

    -- Info "Allowlist Info" header
    -- CreateText reserves ~23px for the title line (16pt + 2px spacer)
    -- before the body starts. This note runs ~200 characters at 12pt --
    -- three wrapped lines needing ~47px of body space. 23 + 47 = 70, plus
    -- a small buffer against font-metric rounding.
    local textRowSize = 76
    local infoRow = GUIFrame:CreateRow(card.content, textRowSize)
    local infoText = GUIFrame:CreateText(infoRow,
        KE:ColorTextByTheme("Allowlist Info"),
        KE:ColorTextByTheme("-") ..
            " This list decides which buffs the display shows. A spell that is not on it, or whose row is switched off, will not appear." ..
            " Only helpful auras on yourself can be filtered this way, which is every external defensive.",
        textRowSize, "hide")
    infoRow:AddWidget(infoText, 1)
    manager:Register(infoText, "all")
    card:AddRow(infoRow, textRowSize)

    -- Separator under the info note
    local sep1Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(sep1Row)
    sep1Row:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
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
            if key and key ~= "" then SelectSpell(tonumber(key)) end
        end,
    })
    selectRow:AddWidget(allowlistDropdown, 0.5, 7, 3)
    manager:Register(allowlistDropdown, "all")

    enabledToggle = GUIFrame:CreateCheckbox(selectRow, "Enabled", {
        value = true,
        callback = function(checked)
            if selectedSpellId and db.Allowlist[selectedSpellId] then
                local entry = db.Allowlist[selectedSpellId]
                if type(entry) == "table" then
                    entry.enabled = checked
                else
                    db.Allowlist[selectedSpellId] = {
                        label   = type(entry) == "string" and entry or nil,
                        enabled = checked,
                    }
                end
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                allowlistDropdown:SetValue(tostring(selectedSpellId), true)
                ApplySettings()
            end
        end,
    })
    selectRow:AddWidget(enabledToggle, 0.5, 3)
    manager:Register(enabledToggle, "all")

    card:AddRow(selectRow, Theme.rowHeight)

    -- Separator under select/toggle row
    local sep2Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(sep2Row)
    sep2Row:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
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
            if KE.AuraRules.CanRekeyAllowlistEntry(db.Allowlist, selectedSpellId, newSpellId) then
                local entry = db.Allowlist[selectedSpellId]
                db.Allowlist[newSpellId] = entry
                db.Allowlist[selectedSpellId] = nil
                selectedSpellId = newSpellId
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                allowlistDropdown:SetValue(tostring(newSpellId), true)
                UpdateSpellDisplay()
                ApplySettings()
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
    manager:Register(spellIdInput, "editableId")

    labelInput = GUIFrame:CreateEditBox(detailRow, "Label", {
        value = "",
        callback = function(text)
            if selectedSpellId and db.Allowlist[selectedSpellId] then
                local entry = db.Allowlist[selectedSpellId]
                if type(entry) == "table" then
                    entry.label = (text and text ~= "") and text or nil
                else
                    db.Allowlist[selectedSpellId] = {
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
    manager:Register(labelInput, "all")
    card:AddRow(detailRow, Theme.rowHeight)

    -- Separator under detail row
    local sep3Row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(sep3Row)
    sep3Row:AddWidget(sep3, 1)
    manager:Register(sep3, "all")
    card:AddRow(sep3Row, Theme.rowHeightSeparator)

    local restoreRowH = Theme.rowHeightLast - 14
    local restoreRow = GUIFrame:CreateRow(card.content, restoreRowH)

    local kitnBtn = GUIFrame:CreateButton(restoreRow, "Kitn Defaults", {
        height = 24,
        callback = function()
            for spellId, seed in pairs(ShippedAllowlist()) do
                db.Allowlist[spellId] = {
                    label   = seed.label,
                    enabled = true,
                    default = true,
                }
            end
            RefreshAllowlist()
        end,
    })
    restoreRow:AddWidget(kitnBtn, 0.5, 7, 3)
    manager:Register(kitnBtn, "all")

    -- Labelled for what it actually reads. "Blizzard Defaults" would claim
    -- this matches Blizzard's own external-defensives frame, and it does not:
    -- it reads the spell-level query, which can disagree with what the
    -- container shows. The tooltip states the limitation in full.
    local blizzBtn = GUIFrame:CreateButton(restoreRow, "Blizzard Flagged", {
        tooltip = "Enables only the spells this client flags as external defensives, and switches the rest off without deleting them. This reads the game's per-spell flag, which can differ from what Blizzard's own external defensives frame shows.",
        height = 24,
        callback = function()
            for spellId, seed in pairs(ShippedAllowlist()) do
                -- Asked per spell rather than read from a stored list, so the
                -- answer follows the game. pcall because a spell id the client
                -- does not know is a plausible input from an edited profile.
                local ok, flagged = pcall(C_Spell.IsExternalDefensive, spellId)
                db.Allowlist[spellId] = {
                    label   = seed.label,
                    -- Switched OFF rather than removed. Deleting would throw
                    -- away a row the user may want back, and the seeded rows
                    -- are undeletable by design anyway.
                    enabled = (ok and flagged) and true or false,
                    default = true,
                }
            end
            RefreshAllowlist()
        end,
    })
    restoreRow:AddWidget(blizzBtn, 0.5, 3)
    manager:Register(blizzBtn, "all")

    card:AddRow(restoreRow, restoreRowH)

    -- Row: Add New Entry + Delete Entry buttons. Uses a shorter row height
    -- to drop the unused gap below the buttons.
    local buttonRowH = Theme.rowHeightLast - 14
    local buttonRow = GUIFrame:CreateRow(card.content, buttonRowH)
    local addBtn = GUIFrame:CreateButton(buttonRow, "Add New Entry", {
        height = 24,
        callback = function()
            local entryNum = 1
            local function labelExists(num)
                local testLabel = "Entry " .. num
                for _, entry in pairs(db.Allowlist) do
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
            while db.Allowlist[newSpellId] do newSpellId = newSpellId - 1 end

            db.Allowlist[newSpellId] = { label = newLabel, enabled = true }

            allowlistDropdown:SetOptions(BuildDropdownOptions())
            allowlistDropdown:SetValue(tostring(newSpellId), true)
            SelectSpell(newSpellId)
            ApplySettings()
        end,
    })
    buttonRow:AddWidget(addBtn, 0.5, 7, 3)
    manager:Register(addBtn, "all")

    deleteBtn = GUIFrame:CreateButton(buttonRow, "Delete Entry", {
        height = 24,
        callback = function()
            if selectedSpellId and db.Allowlist[selectedSpellId] then
                local entry = db.Allowlist[selectedSpellId]
                if type(entry) == "table" and entry.default then return end
                db.Allowlist[selectedSpellId] = nil
                allowlistDropdown:SetOptions(BuildDropdownOptions())
                local nextSpell = GetFirstSpellId()
                if nextSpell then
                    allowlistDropdown:SetValue(tostring(nextSpell), true)
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
    card:AddRow(buttonRow, buttonRowH, 0)

    -- Initial selection
    local firstSpell = GetFirstSpellId()
    if firstSpell then
        SelectSpell(firstSpell)
    else
        spellIconFrame:Hide()
    end

    yOffset = card:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Count Size",  dbKey = "FontSize",      default = 14 },
            { label = "Timer Size",  dbKey = "TimerFontSize", default = 18 },
        },
        fontSizeRange = { 8, 48 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 7: Element Positions
    --
    -- One anchor per element (Timer text / Stack text) drives both
    -- AnchorFrom and AnchorTo — picking "CENTER" aligns the element's
    -- center with the button's center, picking "BOTTOMRIGHT" stacks them
    -- by bottom-right, etc. Mirrors AuraDebuffs' Element Positions card.
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Element Positions", yOffset)
    manager:Register(card7, "all")

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

    db.TimerPosition = db.TimerPosition or {}
    db.StackPosition = db.StackPosition
        or { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = -1, YOffset = 1 }
    local tp, sp = db.TimerPosition, db.StackPosition

    -- Row: Timer Anchor + Timer X + Timer Y (each 1/3 width)
    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local timerAnchor = GUIFrame:CreateDropdown(row7a, "Timer Text Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = tp.AnchorFrom or "CENTER",
        callback = function(key)
            tp.AnchorFrom = key
            tp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7a:AddWidget(timerAnchor, 1 / 3)
    manager:Register(timerAnchor, "all")

    local timerX = GUIFrame:CreateSlider(row7a, "Timer X", {
        min = -50, max = 50, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) tp.XOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerX, 1 / 3)
    manager:Register(timerX, "all")

    local timerY = GUIFrame:CreateSlider(row7a, "Timer Y", {
        min = -50, max = 50, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) tp.YOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerY, 1 / 3)
    manager:Register(timerY, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    -- Separator between Timer and Stack rows
    local row7sep = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    manager:Register(sep7, "all")
    card7:AddRow(row7sep, Theme.rowHeightSeparator)

    -- Row: Stack Anchor + Stack X + Stack Y (each 1/3 width)
    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local stackAnchor = GUIFrame:CreateDropdown(row7b, "Stack Count Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = sp.AnchorFrom or "BOTTOMRIGHT",
        callback = function(key)
            sp.AnchorFrom = key
            sp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7b:AddWidget(stackAnchor, 1 / 3)
    manager:Register(stackAnchor, "all")

    local stackX = GUIFrame:CreateSlider(row7b, "Stack X", {
        min = -50, max = 50, step = 1,
        value = sp.XOffset or -1,
        callback = function(val) sp.XOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackX, 1 / 3)
    manager:Register(stackX, "all")

    local stackY = GUIFrame:CreateSlider(row7b, "Stack Y", {
        min = -50, max = 50, step = 1,
        value = sp.YOffset or 1,
        callback = function(val) sp.YOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackY, 1 / 3)
    manager:Register(stackY, "all")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)
