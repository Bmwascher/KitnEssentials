-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RacialsAnchor.lua                                   ║
-- ║  GUI: Racials Anchor                                     ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           RacialsAnchor module.                          ║
-- ║  Credit: Bitebtw                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame     = KE.GUIFrame
local Theme        = KE.Theme
local table_insert = table.insert

GUIFrame:RegisterContent("RacialsAnchor", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RacialsAnchor
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("RacialsAnchor", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("RacialsAnchor", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("RacialsAnchor")
        else
            KitnEssentials:DisableModule("RacialsAnchor")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled == true
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Racials Anchor (Enable + description)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Racials Anchor", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1,
        "Enable Racials Anchor", db.Enabled == true,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Racials Anchor", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    -- Build the pet-status note appended to the description.
    local mod = KitnEssentials and KitnEssentials:GetModule("RacialsAnchor", true)
    local petNoteColored = ""
    if mod then
        if mod:IsPetFrame() then
            if mod:HasPetBar() then
                petNoteColored = "|cff00ff00- Your current spec has a pet bar visible. |r"
            else
                petNoteColored = "|cffff4444- Your current spec does not have a pet bar visible. |r"
            end
        end
    end

    local noteLines = KE:ColorTextByTheme("-") .. " Repositions Ayije CDM_RacialsContainer with custom anchor and offset settings."
    if petNoteColored ~= "" then
        noteLines = noteLines .. "\n" .. petNoteColored
    end
    local noteHeight = petNoteColored ~= "" and 50 or 35
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        noteLines,
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Offset Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Anchor Settings", yOffset)
    table_insert(allWidgets, card2)

    card2:AddLabel("|cff888888Overrides CDM's anchor points and offsets. Set to CDM Default to pass through.|r")

    -- Anchor point dropdowns
    local anchorPoints = {
        { key = "",            text = "CDM Default" },
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

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local selfPointDropdown = GUIFrame:CreateDropdown(row2a, "Container Anchor",
        anchorPoints, db.AnchorFrom or "", 80,
        function(key)
            db.AnchorFrom = key
            ApplySettings()
        end)
    row2a:AddWidget(selfPointDropdown, 0.5)
    table_insert(allWidgets, selfPointDropdown)

    local attachPointDropdown = GUIFrame:CreateDropdown(row2a, "Attach To",
        anchorPoints, db.AnchorTo or "", 80,
        function(key)
            db.AnchorTo = key
            ApplySettings()
        end)
    row2a:AddWidget(attachPointDropdown, 0.5)
    table_insert(allWidgets, attachPointDropdown)
    card2:AddRow(row2a, 40)

    -- Row: X Offset + Y Offset sliders
    local row2c = GUIFrame:CreateRow(card2.content, 40)

    local xSlider = GUIFrame:CreateSlider(row2c, "X Offset", -200, 200, 1,
        db.XOffset or 0, 60,
        function(val)
            db.XOffset = val
            ApplySettings()
        end)
    row2c:AddWidget(xSlider, 0.5)
    table_insert(allWidgets, xSlider)

    local ySlider = GUIFrame:CreateSlider(row2c, "Y Offset", -200, 200, 1,
        db.YOffset or -2, 60,
        function(val)
            db.YOffset = val
            ApplySettings()
        end)
    row2c:AddWidget(ySlider, 0.5)
    table_insert(allWidgets, ySlider)
    card2:AddRow(row2c, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Pet Bar Offset
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Pet Bar Offset", yOffset)
    table_insert(allWidgets, card3)

    local row3 = GUIFrame:CreateRow(card3.content, 40)
    local petOffsetSlider = GUIFrame:CreateSlider(row3, "Pet Bar Offset", -50, 50, 1,
        db.PetBarOffset or -1, 60,
        function(val)
            db.PetBarOffset = val
            ApplySettings()
        end)
    row3:AddWidget(petOffsetSlider, 1)
    table_insert(allWidgets, petOffsetSlider)
    card3:AddRow(row3, 40)

    card3:AddLabel("|cff888888Additional Y offset applied when pet bar is visible. \nSupports ElvUI (ElvUF_Pet) and Unhalted Unit Frames (UUF_Pet) pet frames.|r")

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Final widget state sync
    ---------------------------------------------------------------------------------
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
