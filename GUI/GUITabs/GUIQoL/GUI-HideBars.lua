-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

local function GetHideBarsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("HideBars", true)
    end
    return nil
end

local function FormatKeybind(key)
    if not key or key == "" then return "Not Set" end
    return key
end

GUIFrame:RegisterContent("HideBars", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.HideBars
    if not db then return yOffset end

    local HB = GetHideBarsModule()
    local allWidgets = {}

    local function ApplyModuleState(enabled)
        if not HB then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("HideBars")
        else KitnEssentials:DisableModule("HideBars") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Hide ActionBars", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Hide ActionBars", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Hide ActionBars", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Bar Selection
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bar Selection", yOffset)
    table_insert(allWidgets, card2)

    local barNames = { "Bar 1", "Bar 2", "Bar 3", "Bar 4", "Bar 5", "Bar 6" }

    local row2a = GUIFrame:CreateRow(card2.content, 36)
    for i = 1, 3 do
        local check = GUIFrame:CreateCheckbox(row2a, barNames[i], db.Bars[i] == true,
            function(checked) db.Bars[i] = checked end)
        row2a:AddWidget(check, 1 / 3)
        table_insert(allWidgets, check)
    end
    card2:AddRow(row2a, 36)

    local row2b = GUIFrame:CreateRow(card2.content, 36)
    for i = 4, 6 do
        local check = GUIFrame:CreateCheckbox(row2b, barNames[i], db.Bars[i] == true,
            function(checked) db.Bars[i] = checked end)
        row2b:AddWidget(check, 1 / 3)
        table_insert(allWidgets, check)
    end
    card2:AddRow(row2b, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Keybind
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Keybind", yOffset)
    table_insert(allWidgets, card3)

    local keybindRow = GUIFrame:CreateRow(card3.content, 36)
    local isListening = false
    local keybindBtn

    local function StopListening()
        isListening = false
        if keybindBtn and keybindBtn.SetLabel then
            keybindBtn:SetLabel(FormatKeybind(db.Keybind))
        end
        if keybindBtn then
            keybindBtn:EnableKeyboard(false)
            keybindBtn:SetScript("OnKeyDown", nil)
        end
    end

    local function StartListening()
        isListening = true
        if keybindBtn and keybindBtn.SetLabel then
            keybindBtn:SetLabel("|cffFFCC00Press a key...|r")
        end
        if keybindBtn then
            keybindBtn:EnableKeyboard(true)
            keybindBtn:SetScript("OnKeyDown", function(_, key)
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                    or key == "LALT" or key == "RALT" then
                    return
                end
                if key == "ESCAPE" then
                    StopListening()
                    return
                end
                local bind = ""
                if IsShiftKeyDown() then bind = bind .. "SHIFT-" end
                if IsControlKeyDown() then bind = bind .. "CTRL-" end
                if IsAltKeyDown() then bind = bind .. "ALT-" end
                bind = bind .. key
                db.Keybind = bind
                StopListening()
                if HB then HB:ApplyKeybind() end
            end)
        end
    end

    keybindBtn = GUIFrame:CreateButton(keybindRow, FormatKeybind(db.Keybind), {
        width = 160,
        height = 26,
        callback = function()
            if isListening then StopListening() else StartListening() end
        end,
    })
    keybindRow:AddWidget(keybindBtn, 0.5)

    local clearBtn = GUIFrame:CreateButton(keybindRow, "Clear", {
        width = 80,
        height = 26,
        callback = function()
            db.Keybind = ""
            StopListening()
            if keybindBtn and keybindBtn.SetLabel then
                keybindBtn:SetLabel("Not Set")
            end
            if HB then HB:ClearKeybind() end
        end,
    })
    keybindRow:AddWidget(clearBtn, 0.5)

    card3:AddRow(keybindRow, 36)
    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Note
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Note", yOffset)
    table_insert(allWidgets, card4)

    local noteWidget = GUIFrame:CreateText(card4.content,
        KE:ColorTextByTheme("Out of Combat Only"),
        "The keybind will only work out of combat. Action bars cannot be toggled during combat due to Blizzard's secure frame restrictions. Select which ElvUI bars to toggle above.",
        60, "hide", true)
    card4:AddRow(noteWidget, 60)
    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
