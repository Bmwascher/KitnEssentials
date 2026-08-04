-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CopyAnything.lua                                    ║
-- ║  GUI: Copy Anything                                      ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           CopyAnything module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CopyAnything", true)
    end
    return nil
end

GUIFrame:RegisterContent("CopyAnything", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CopyAnything
    if not db then return yOffset end

    local CA = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if CA then CA:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not CA then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("CopyAnything")
        else KitnEssentials:DisableModule("CopyAnything") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local modifierList = {
        { key = "ctrl",  text = "Ctrl" },
        { key = "shift", text = "Shift" },
        { key = "alt",   text = "Alt" },
    }

    local keyList = {}
    for i = 0, 25 do
        local letter = string.char(65 + i)
        keyList[#keyList + 1] = { key = letter, text = letter }
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Copy Anything", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
        KE:Print("Copy Anything: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Hover anything with a tooltip and press your copy key to open a small window with its ID ready to copy. Does nothing in combat or in a Mythic+ run.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeight, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Copy Key Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Copy Key Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local modifierDropdown = GUIFrame:CreateDropdown(row2, "Modifier", {
        options = modifierList,
        value = db.Modifier or "ctrl",
        callback = function(key)
            db.Modifier = key
            ApplySettings()
        end,
    })
    row2:AddWidget(modifierDropdown, 0.5)
    manager:Register(modifierDropdown, "all")

    local keyDropdown = GUIFrame:CreateDropdown(row2, "Key", {
        options = keyList,
        value = db.Key or "C",
        callback = function(key)
            db.Key = key
            ApplySettings()
        end,
    })
    row2:AddWidget(keyDropdown, 0.5)
    manager:Register(keyDropdown, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    RefreshStates()
    return yOffset
end)
