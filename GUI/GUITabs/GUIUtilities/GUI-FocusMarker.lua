-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FocusMarker.lua                                     ║
-- ║  GUI: Focus Marker                                       ║
-- ║  Purpose: Configuration panel for the FocusMarker module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs

local function GetModule()
    return KitnEssentials:GetModule("FocusMarker", true)
end

-- Marker options with inline icon textures for dropdown display
local MARKER_OPTIONS = {
    { key = "Star",     text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:16|t  Star" },
    { key = "Circle",   text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:16|t  Circle" },
    { key = "Diamond",  text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:16|t  Diamond" },
    { key = "Triangle", text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:16|t  Triangle" },
    { key = "Moon",     text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:16|t  Moon" },
    { key = "Square",   text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:16|t  Square" },
    { key = "Cross",    text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:16|t  Cross" },
    { key = "Skull",    text = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t  Skull" },
    { key = "None",     text = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:16|t  None" },
}

GUIFrame:RegisterContent("FocusMarker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.FocusMarker
    if not db then return yOffset end

    local FM = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if FM and FM.ApplySettings then FM:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not FM then return end
        FM.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("FocusMarker")
        else
            KitnEssentials:DisableModule("FocusMarker")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Focus Marker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Focus Marker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Focus Marker", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-creates a macro for focus targeting + raid marker assignment.\n" .. KE:ColorTextByTheme("-") .. " Drag the macro from /macro to your action bar.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Marker Selection (icon grid)
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Marker Selection", yOffset)
    table_insert(allWidgets, card2)

    local ICON_SIZE = 40
    local ICON_SPACING = 8
    local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
    local MARKER_ORDER = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull", "None" }
    local MARKER_INDEX = { Star=1, Circle=2, Diamond=3, Triangle=4, Moon=5, Square=6, Cross=7, Skull=8 }
    local totalWidth = (#MARKER_ORDER * ICON_SIZE) + ((#MARKER_ORDER - 1) * ICON_SPACING)
    local gridRowHeight = ICON_SIZE + 8
    local gridRow = GUIFrame:CreateRow(card2.content, gridRowHeight)
    local gridContainer = CreateFrame("Frame", nil, gridRow)
    gridContainer:SetSize(totalWidth, gridRowHeight)
    gridContainer:SetPoint("CENTER", gridRow, "CENTER", 0, 0)

    local selectedLabel = gridRow:CreateFontString(nil, "OVERLAY")
    selectedLabel:SetPoint("TOP", gridContainer, "BOTTOM", 0, -4)
    KE:ApplyThemeFont(selectedLabel, "normal")
    selectedLabel:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    selectedLabel:SetText(db.SelectedMarker or "Star")

    local markerButtons = {}

    local function UpdateMarkerSelection()
        local sel = db.SelectedMarker or "Star"
        for _, btn in ipairs(markerButtons) do
            if btn.markerName == sel then
                btn.border:Show()
                btn:SetAlpha(1)
                selectedLabel:ClearAllPoints()
                selectedLabel:SetPoint("TOP", btn, "BOTTOM", 0, -4)
            else
                btn.border:Hide()
                btn:SetAlpha(0.5)
            end
        end
        selectedLabel:SetText(sel)
    end

    for i, name in ipairs(MARKER_ORDER) do
        local btn = CreateFrame("Button", nil, gridContainer)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("LEFT", gridContainer, "LEFT", (i - 1) * (ICON_SIZE + ICON_SPACING), 0)
        btn.markerName = name

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        if MARKER_INDEX[name] then
            icon:SetTexture(MARKER_TEX .. MARKER_INDEX[name])
        else
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        end

        -- Accent border frame (shown on selected)
        local borderFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        borderFrame:SetAllPoints()
        borderFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        borderFrame:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        borderFrame:Hide()
        btn.border = borderFrame

        -- Hover highlight
        btn:SetScript("OnEnter", function(self)
            if self.markerName ~= db.SelectedMarker then
                self:SetAlpha(0.8)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.markerName ~= db.SelectedMarker then
                self:SetAlpha(0.5)
            end
        end)

        btn:SetScript("OnClick", function(self)
            db.SelectedMarker = self.markerName
            UpdateMarkerSelection()
            ApplySettings()
        end)

        table_insert(markerButtons, btn)
    end

    card2:AddRow(gridRow, gridRowHeight + 24) -- extra space for the name label below

    UpdateMarkerSelection()

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Macro Options
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Macro Options", yOffset)
    table_insert(allWidgets, card3)

    local macroOptionDefs = {
        { key = "MarkOnly",   label = "Mark Only",   desc = "Only apply raid marker, do not set focus.", default = false },
        { key = "NoRaid",     label = "No Raid Marking", desc = "Don't apply marker while in raid group.", default = false },
        { key = "NoToggle",   label = "No Toggle",   desc = "Prevent marker from toggling off on repeated clicks.", default = true },
        { key = "AnnounceReadyCheck", label = "Ready Check Announce", desc = "Announce your marker in party chat on ready check.", default = true },
    }

    for _, def in ipairs(macroOptionDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local label = def.label .. "  |cff888888- " .. def.desc .. "|r"
        local row = GUIFrame:CreateRow(card3.content, 38)
        local checkbox = GUIFrame:CreateCheckbox(row, label, checked,
            function(val) db[def.key] = val; ApplySettings() end)
        row:AddWidget(checkbox, 1)
        table_insert(allWidgets, checkbox)
        card3:AddRow(row, 38)
    end

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Advanced
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Advanced", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local nameEditBox = GUIFrame:CreateEditBox(row4a, "Macro Name", db.MacroName or "FocusMarker",
        function(val)
            if val and val ~= "" then
                db.MacroName = val
            else
                db.MacroName = "FocusMarker"
            end
            ApplySettings()
        end)
    row4a:AddWidget(nameEditBox, 0.5)
    table_insert(allWidgets, nameEditBox)

    local iconEditBox = GUIFrame:CreateEditBox(row4a, "Macro Icon ID", tostring(db.MacroIcon or 1033497),
        function(val)
            local num = tonumber(val)
            if num then
                db.MacroIcon = num
                ApplySettings()
            end
        end)
    row4a:AddWidget(iconEditBox, 0.5)
    table_insert(allWidgets, iconEditBox)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local condEditBox = GUIFrame:CreateEditBox(row4b, "Macro Conditionals (empty = default)", db.MacroConditionals or "",
        function(val)
            db.MacroConditionals = val or ""
            ApplySettings()
        end)
    row4b:AddWidget(condEditBox, 1)
    table_insert(allWidgets, condEditBox)
    card4:AddRow(row4b, 40)

    local advNoteHeight = 75
    local advNoteRow = GUIFrame:CreateRow(card4.content, advNoteHeight)
    local advNoteText = GUIFrame:CreateText(advNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Leave conditionals empty to use default: [@mouseover,exists,nodead][]\n" .. KE:ColorTextByTheme("-") .. " Macro icon accepts numeric icon IDs.\n   " .. KE:ColorTextByTheme(">") .. " Find IDs by clicking any spell or item icon on Wowhead.",
        advNoteHeight, "hide")
    advNoteRow:AddWidget(advNoteText, 1)
    card4:AddRow(advNoteRow, advNoteHeight)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
