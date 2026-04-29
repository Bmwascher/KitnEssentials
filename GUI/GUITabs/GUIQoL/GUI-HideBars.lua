-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HideBars.lua                                        ║
-- ║  GUI: Hide ActionBars                                    ║
-- ║  Purpose: Configuration panel for the HideBars module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
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

    local HB = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyModuleState(enabled)
        if not HB then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("HideBars")
        else KitnEssentials:DisableModule("HideBars") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Hide ActionBars", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Hide ActionBars", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Hide ActionBars",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Bar Selection
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bar Selection", yOffset)
    manager:Register(card2, "all")

    local barNames = { "Bar 1", "Bar 2", "Bar 3", "Bar 4", "Bar 5", "Bar 6" }

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    for i = 1, 3 do
        local check = GUIFrame:CreateCheckbox(row2a, barNames[i], {
            value = db.Bars[i] == true,
            callback = function(checked) db.Bars[i] = checked end,
        })
        row2a:AddWidget(check, 1/3)
        manager:Register(check, "all")
    end
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    for i = 4, 6 do
        local check = GUIFrame:CreateCheckbox(row2b, barNames[i], {
            value = db.Bars[i] == true,
            callback = function(checked) db.Bars[i] = checked end,
        })
        row2b:AddWidget(check, 1/3)
        manager:Register(check, "all")
    end
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Keybind (custom capture button)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Keybind", yOffset)
    manager:Register(card3, "all")

    local keybindRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
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
    manager:Register(keybindBtn, "all")

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
    manager:Register(clearBtn, "all")
    card3:AddRow(keybindRow, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Note
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Note", yOffset)
    manager:Register(card4, "all")

    local noteRow = GUIFrame:CreateRow(card4.content, 60)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Out of Combat Only"),
        KE:ColorTextByTheme("-") .. " The keybind will only work out of combat. Action bars cannot be toggled\n  during combat due to Blizzard's secure frame restrictions.",
        60, "hide")
    noteRow:AddWidget(noteText, 1)
    card4:AddRow(noteRow, 60, 0)

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)
