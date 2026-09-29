-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FocusMarker.lua                                     ║
-- ║  GUI: Focus Macros                                       ║
-- ║  Purpose: Configuration panel for the FocusMarker module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local MARKER_ORDER = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull", "None" }
local MARKER_INDEX = { Star=1, Circle=2, Diamond=3, Triangle=4, Moon=5, Square=6, Cross=7, Skull=8 }
local MARKER_NONE_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local CLASS_ORDER = {
    { token = "DEATHKNIGHT", name = "Death Knight" },
    { token = "DEMONHUNTER", name = "Demon Hunter" },
    { token = "DRUID",       name = "Druid" },
    { token = "EVOKER",      name = "Evoker" },
    { token = "HUNTER",      name = "Hunter" },
    { token = "MAGE",        name = "Mage" },
    { token = "MONK",        name = "Monk" },
    { token = "PALADIN",     name = "Paladin" },
    { token = "PRIEST",      name = "Priest" },
    { token = "ROGUE",       name = "Rogue" },
    { token = "SHAMAN",      name = "Shaman" },
    { token = "WARLOCK",     name = "Warlock" },
    { token = "WARRIOR",     name = "Warrior" },
}

local KICK_ALL_ON = {
    KickStopCasting = true,
    KickMouseover = true,
    KickTargetFallback = true,
    KickMarkFocus = true,
}

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("FocusMarker", true)
    end
    return nil
end

local function GetDB()
    return KE.db and KE.db.profile.FocusMarker
end

local function ApplySettings()
    local FM = GetModule()
    if FM and FM.ApplySettings then FM:ApplySettings() end
end

-- A frame late, so the widget whose callback asked for it is not torn down mid-call.
local function RefreshSoon()
    C_Timer.After(0, function() GUIFrame:RefreshContent() end)
end

local function ClassName(token)
    for _, info in ipairs(CLASS_ORDER) do
        if info.token == token then return info.name end
    end
    return token
end

-- Macro names, like addon names and slash commands, read in gold.
local function Gold(text)
    return "|cffffd100" .. text .. "|r"
end

-- Both preview cards: a heading, the length against the macro limit, then the
-- body. A macro name closing the heading keeps its gold.
local function AddPreviewSection(card, heading, body, bodyMax, macroName)
    card:AddLabel(KE:ColorTextByTheme(heading) .. (macroName or ""))
    card:AddLabel("|cff888888" .. #body .. " of " .. bodyMax .. " characters, read-only|r")
    card:AddLabel(body)
end

local function Unavailable(scrollChild, yOffset)
    local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
    errorCard:AddLabel("Focus Macros is not available.")
    return errorCard:GetNextOffset()
end

----------------------------------------------------------------
-- Header: the module switch, above the tab strip
----------------------------------------------------------------
local function BuildHeader(scrollChild, yOffset)
    local db = GetDB()
    if not db then return Unavailable(scrollChild, yOffset), true end

    local card = GUIFrame:CreateCard(scrollChild, "Focus Macros", yOffset)
    card:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if not GetModule() then return end
        if checked then
            KitnEssentials:EnableModule("FocusMarker")
        else
            KitnEssentials:DisableModule("FocusMarker")
        end
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else. Any
    -- label would give the card a body, and collapse only hides the tabs.
    local disabled = db.Enabled == false
    if not disabled then
        local FM = GetModule()
        local kickName = FM and (", " .. Gold(FM.KICK_MACRO_NAME) .. ",") or ""
        card:AddLabel("Writes a macro that sets your focus and puts your marker on it in one press, so " ..
            "a kick target can be called and taken together. The Focus Kick tab can add a second macro" ..
            kickName .. " that casts your interrupt at that focus. Drag either from |cffffd100/macro|r onto " ..
            "a bar; both are kept up to date as you change the settings below." ..
            "\n\nThe marker macro goes for whatever is under your mouse, and falls back to your current " ..
            "target." ..
            "\n\nTurning this off leaves both macros alone rather than deleting them, in case you have put " ..
            "them on a bar.")
    end

    return card:GetNextOffset(), disabled
end

----------------------------------------------------------------
-- Focus Marker tab
----------------------------------------------------------------
GUIFrame:RegisterContent("FocusMarkerMarker", function(scrollChild, yOffset)
    local db = GetDB()
    if not db then return Unavailable(scrollChild, yOffset) end

    local FM = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    local classFile = FM and FM:GetPlayerClass()
    local classMode = db.MarkerFromClass == true
    local editsClass = classMode and classFile ~= nil and db.ClassMarkers ~= nil

    local function EffectiveMarker()
        return (FM and FM:GetEffectiveMarker()) or db.SelectedMarker or "Star"
    end

    ----------------------------------------------------------------
    -- Marker Selection: the class switch, then the icon grid
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Marker Selection", yOffset)
    manager:Register(card2, "all")

    local classRow = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local classCheck = GUIFrame:CreateCheckbox(classRow, "Marker From Class  |cff888888- Use the marker set for " ..
        "your class in Class Markers instead of one marker for every character.|r", {
        value = classMode,
        callback = function(val)
            db.MarkerFromClass = val
            ApplySettings()
            RefreshSoon()
        end,
    })
    classRow:AddWidget(classCheck, 1)
    manager:Register(classCheck, "all")
    card2:AddRow(classRow, Theme.rowHeight)

    if editsClass then
        local className = ClassName(classFile)
        card2:AddLabel("Your class: " .. GUIFrame.ClassIconText(classFile) ..
            KE:ColorTextByClass(className, classFile) ..
            "  |cff888888- click a marker to change " .. className .. "'s marker.|r")
    end

    local ICON_SIZE = 40
    local ICON_SPACING = 8
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
    selectedLabel:SetText(EffectiveMarker())

    local markerButtons = {}

    local function UpdateMarkerSelection()
        local sel = EffectiveMarker()
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
            icon:SetTexture(MARKER_NONE_TEX)
        end

        local borderFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        borderFrame:SetAllPoints()
        borderFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        borderFrame:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        borderFrame:Hide()
        btn.border = borderFrame

        btn:SetScript("OnEnter", function(self)
            if self.markerName ~= EffectiveMarker() then
                self:SetAlpha(0.8)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.markerName ~= EffectiveMarker() then
                self:SetAlpha(0.5)
            end
        end)

        -- In class mode the grid edits your own class's entry, so a click is never silently ignored.
        btn:SetScript("OnClick", function(self)
            if editsClass then
                db.ClassMarkers[classFile] = self.markerName
            else
                db.SelectedMarker = self.markerName
            end
            UpdateMarkerSelection()
            ApplySettings()
            RefreshSoon()
        end)

        table.insert(markerButtons, btn)
    end

    card2:AddRow(gridRow, gridRowHeight + 24, 0)

    UpdateMarkerSelection()

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Class Markers: a class picker and that class's marker, only while the
    -- class option is on
    ----------------------------------------------------------------
    if classMode and db.ClassMarkers then
        local root = KE.GetDefaultDB and KE:GetDefaultDB()
        local section = root and root.profile and root.profile.FocusMarker
        local shipped = (section and section.ClassMarkers) or {}

        local markerOptions = {}
        for _, name in ipairs(MARKER_ORDER) do
            local tex = MARKER_INDEX[name] and (MARKER_TEX .. MARKER_INDEX[name]) or MARKER_NONE_TEX
            markerOptions[#markerOptions + 1] = { value = name, text = "|T" .. tex .. ":16:16|t " .. name }
        end

        local classTokens = {}
        for i, info in ipairs(CLASS_ORDER) do classTokens[i] = info.token end

        local cardClass = GUIFrame:CreateCard(scrollChild, "Class Markers", yOffset)
        manager:Register(cardClass, "all")
        cardClass:AddLabel("Each character uses its class's marker. Pick a class to see or change its marker; " ..
            "clicking the grid above changes your own class's.")

        local pickerRow, token = GUIFrame:CreateClassPickerRow(cardClass.content, {
            scope = "FocusMarkerClass",
            classTokens = classTokens,
            label = "Class",
        })
        cardClass:AddRow(pickerRow, 36)

        local current = db.ClassMarkers[token]
        local default = shipped[token]
        local isOverride = default ~= nil and current ~= default
        local label = KE:ColorTextByClass(ClassName(token), token) .. " Marker"
        if isOverride then
            label = label .. "  |cff888888override, default: " .. default .. "|r"
        end

        local row = GUIFrame:CreateRow(cardClass.content, Theme.rowHeightLast)
        local dropdown = GUIFrame:CreateDropdown(row, label, {
            options = markerOptions,
            value = current,
            callback = function(val)
                db.ClassMarkers[token] = val
                ApplySettings()
                RefreshSoon()
            end,
        })
        row:AddWidget(dropdown, isOverride and 0.75 or 1)
        manager:Register(dropdown, "all")

        if isOverride then
            local resetButton = GUIFrame:CreateButton(row, "Reset", {
                callback = function()
                    db.ClassMarkers[token] = default
                    ApplySettings()
                    RefreshSoon()
                end,
            })
            row:AddWidget(resetButton, 0.25)
        end
        cardClass:AddRow(row, Theme.rowHeightLast, 0)

        yOffset = cardClass:GetNextOffset()
    end

    ----------------------------------------------------------------
    -- Macro Options
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Macro Options", yOffset)
    manager:Register(card3, "all")

    local macroOptionDefs = {
        { key = "MarkOnly", label = "Mark Only",
          desc = "Only apply raid marker, do not set focus.", default = false },
        { key = "NoRaid", label = "No Raid Marking",
          desc = "Don't apply marker while in raid group.", default = false },
        { key = "NoToggle", label = "No Toggle",
          desc = "Prevent marker from toggling off on repeated clicks.", default = true },
        { key = "NoOverwrite", label = "No Overwrite",
          desc = "Skip marking targets that are already marked.", default = true },
        { key = "AnnounceReadyCheck", label = "Ready Check Announce",
          desc = "Announce your marker in party chat on ready check.", default = true },
    }

    for i, def in ipairs(macroOptionDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local label = def.label .. "  |cff888888- " .. def.desc .. "|r"
        local isLast = i == #macroOptionDefs
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card3.content, rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, label, {
            value = checked,
            callback = function(val) db[def.key] = val; ApplySettings(); RefreshSoon() end,
        })
        row:AddWidget(checkbox, 1)
        manager:Register(checkbox, "all")
        if isLast then
            card3:AddRow(row, rowHeight, 0)
        else
            card3:AddRow(row, rowHeight)
        end
    end

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Marker Preview
    ----------------------------------------------------------------
    local cardMarker = GUIFrame:CreateCard(scrollChild, "Marker Preview", yOffset)
    manager:Register(cardMarker, "all")
    local markerBody = FM and FM:BuildMacroBody()
    if markerBody then
        AddPreviewSection(cardMarker, "What KE writes to ", markerBody, FM.MACRO_BODY_MAX,
            Gold(db.MacroName or "!FocusMarker"))
    else
        cardMarker:AddLabel("Nothing to preview.")
    end

    yOffset = cardMarker:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)

----------------------------------------------------------------
-- Focus Kick tab
----------------------------------------------------------------
GUIFrame:RegisterContent("FocusMarkerKick", function(scrollChild, yOffset)
    local db = GetDB()
    local FM = GetModule()
    if not db or not FM then return Unavailable(scrollChild, yOffset) end

    local kickName = Gold(FM.KICK_MACRO_NAME)
    local bodyMax = FM.MACRO_BODY_MAX

    -- Writes before the page rebuilds, so the status below reads the result
    -- rather than a write still queued for the next frame.
    local function ApplyKickNow()
        ApplySettings()
        FM:RefreshKickMacro()
    end

    local cardKick = GUIFrame:CreateCard(scrollChild, "Focus Kick Macro", yOffset)
    cardKick:AddHeaderToggle(db.KickMacroEnabled == true, function(checked)
        db.KickMacroEnabled = checked
        ApplyKickNow()
    end)
    cardKick:AddLabel("One per-character macro, " .. kickName .. ", that casts your interrupt at your focus. " ..
        "Rewritten when you change spec or pet; left as it was on a spec with no interrupt. It never " ..
        "touches your other macros.")
    yOffset = cardKick:GetNextOffset()

    if db.KickMacroEnabled ~= true then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()
    local state, spellID, body, specName, spellName = FM:ComputeKick()
    local specText = specName or "this spec"
    local spellText = spellName or "?"
    local markerName = FM:GetEffectiveMarker() or "Star"
    local markerIdx = MARKER_INDEX[markerName] or 0

    ----------------------------------------------------------------
    -- Current Spec: what the macro casts now, or why it was left alone.
    -- Read when the page is built; events never rebuild the page.
    ----------------------------------------------------------------
    local cardSpec = GUIFrame:CreateCard(scrollChild, "Current Spec", yOffset)
    manager:Register(cardSpec, "all")

    local status
    if state == "nospec" then
        status = "Your spec has not loaded yet."
    elseif state == "nokick" then
        cardSpec:AddLabel("No interrupt known  -  " .. specText)
        status = "No interrupt is known for " .. specText .. " right now (none in this spec, not talented, " ..
            "or no demon out). " .. kickName .. " left as it was."
    elseif state == "loading" then
        cardSpec:AddLabel("Loading spell data  -  " .. specText)
        status = "Loading spell data; " .. kickName .. " updates when it arrives."
    else
        local icon = spellID and C_Spell.GetSpellTexture(spellID)
        local iconText = icon and ("|T" .. icon .. ":16:16|t ") or ""
        cardSpec:AddLabel(iconText .. spellText .. "  -  " .. specText)
        if state == "toolong" then
            status = "The macro would be longer than " .. bodyMax .. " characters; " .. kickName ..
                " left as it was."
        elseif FM.kickSlotsFull then
            status = "Character macro slots full (" .. FM.MAX_CHARACTER_MACROS .. "/" .. FM.MAX_CHARACTER_MACROS ..
                "). Free a slot; KE tries again on your next spec change or /reload."
        elseif FM:ReadKickBody() ~= body then
            status = kickName .. " has not been written yet; if this stays, the reason is in chat."
        elseif FM:GetPlayerClass() == "WARLOCK" then
            status = kickName .. " written for " .. spellText .. ". Summoning a different demon rewrites it."
        else
            status = kickName .. " is up to date. Drag it from |cffffd100/macro|r (character tab) onto a bar."
        end
    end
    cardSpec:AddLabel(status)
    yOffset = cardSpec:GetNextOffset()

    ----------------------------------------------------------------
    -- Macro Options
    ----------------------------------------------------------------
    local cardOptions = GUIFrame:CreateCard(scrollChild, "Macro Options", yOffset)
    manager:Register(cardOptions, "all")

    local markDesc = "Also put your marker (" .. markerName .. ") on your focus. The marker macro already does this."
    if markerIdx == 0 then
        markDesc = "Also put your marker on your focus. Your marker is None, so no mark line is written."
    end

    local kickOptionDefs = {
        { key = "KickMouseover", label = "Mouseover Step",
          desc = "With no focus, kick the enemy under your mouse before trying your target." },
        { key = "KickTargetFallback", label = "Target Fallback",
          desc = "With no focus, kick your current target." },
        { key = "KickStopCasting", label = "Stop Casting",
          desc = "Cancel your own cast first. It also cancels your cast while the kick is on cooldown." },
        { key = "KickMarkFocus", label = "Mark Focus", desc = markDesc },
    }

    for i, def in ipairs(kickOptionDefs) do
        local isLast = i == #kickOptionDefs
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(cardOptions.content, rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, def.label .. "  |cff888888- " .. def.desc .. "|r", {
            value = db[def.key] == true,
            callback = function(val)
                db[def.key] = val
                ApplyKickNow()
                RefreshSoon()
            end,
        })
        row:AddWidget(checkbox, 1)
        manager:Register(checkbox, "all")
        if isLast then
            cardOptions:AddRow(row, rowHeight, 0)
        else
            cardOptions:AddRow(row, rowHeight)
        end
    end

    yOffset = cardOptions:GetNextOffset()

    ----------------------------------------------------------------
    -- Macro Preview: the body written now, then the longest one the
    -- options can make
    ----------------------------------------------------------------
    local cardPreview = GUIFrame:CreateCard(scrollChild, "Macro Preview", yOffset)
    manager:Register(cardPreview, "all")

    if body then
        AddPreviewSection(cardPreview, "What KE writes to ", body, bodyMax, kickName)
        local fullBody = spellName and FM.BuildKickBody(spellName, KICK_ALL_ON, markerIdx)
        if fullBody then
            local sepRow = GUIFrame:CreateRow(cardPreview.content, Theme.rowHeightSeparator)
            sepRow:AddWidget(GUIFrame:CreateSeparator(sepRow), 1)
            cardPreview:AddRow(sepRow, Theme.rowHeightSeparator)
            AddPreviewSection(cardPreview, "With every option on", fullBody, bodyMax)
        end
    else
        cardPreview:AddLabel("Nothing to preview for this spec.")
    end

    yOffset = cardPreview:GetNextOffset()

    manager:UpdateAll(true)
    return yOffset
end)

----------------------------------------------------------------
-- Host: the module switch above a Focus Marker | Focus Kick strip
----------------------------------------------------------------
GUIFrame:RegisterTabbedContent("FocusMarker", {
    { id = "FocusMarkerMarker", label = "Focus Marker" },
    { id = "FocusMarkerKick",   label = "Focus Kick" },
}, {
    headerBuilder = BuildHeader,
})
