-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RestedXP.lua                                        ║
-- ║  GUI: RestedXP                                           ║
-- ║  Purpose: Configuration panel for the SkinRestedXP       ║
-- ║  module: the host, its header, the General tab and the   ║
-- ║  preview dialog.                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UIParent = UIParent
local ipairs, tostring = ipairs, tostring

local Safe, Rules, Setup, Look = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPSetup, KE.RestedXPTheme

local PAGE_ID = "SkinRestedXP"
local TAB_GENERAL = "SkinRestedXPGeneral"
local TAB_ARROW = "SkinRestedXPArrow"
local TAB_WINDOW = "SkinRestedXPWindow"
local RXP_ADDON = "RXPGuides"

local TEXT_SETUP_TITLE = "Set up RestedXP for this character?"
local TEXT_SETUP_BODY = "KitnEssentials will change these RestedXP settings for this character. Undo Setup puts them back."
local TEXT_UNDO_TITLE = "Undo RestedXP setup for this character?"
local TEXT_UNDO_BODY = "KitnEssentials will put these RestedXP settings back for this character."
local TEXT_RELOAD_NOTE = "RestedXP reads the V2 setting when it loads, so this ends with a reload."
local TEXT_REASON = " is off, because RestedXP no longer has a call it needs."

local DIALOG_WIDTH, DIALOG_PAD, DIALOG_ROW, DIALOG_GAP, BUTTON_H, BUTTON_W = 430, 14, 18, 10, 26, 150
local COLUMNS = { 0, 170, 290 }
local MAX_ROWS = 3

local LOOK_OPTIONS = {
    { key = "window", text = "KE Guide Window" },
    { key = "own", text = "RestedXP's Own" },
    { key = "colors", text = "KE Colors on RestedXP's Windows" },
}
local ICON_OPTIONS = {
    { key = "ke", text = "KE Icons" },
    { key = "own", text = "RestedXP's Own" },
}
local PART_LABELS = {
    { key = "Theme", label = "Theme" },
    { key = "Arrow", label = "Arrow" },
    { key = "Icons", label = "Step Icons" },
    { key = "Window", label = "Guide Window" },
    { key = "Setup", label = "Set Up This Character" },
}

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule(PAGE_ID, true)
end

local function Installed()
    return C_AddOns.DoesAddOnExist(RXP_ADDON) == true
end

-- A refresh rebuilds whichever page is in view and fires its waiting widget
-- callbacks, so it runs only for this page. A hidden window marks itself dirty and
-- rebuilds when it opens.
local function RebuildPage()
    C_Timer.After(0, function()
        if GUIFrame.selectedSidebarItem == PAGE_ID then GUIFrame:RefreshContent() end
    end)
end

---------------------------------------------------------------------------------
-- The preview dialog
---------------------------------------------------------------------------------
local dialog
local OpenDialog

-- An open preview shows the rows a write would make now, or closes when there are
-- none.
local function ShowCurrentRows()
    if not (dialog and dialog:IsShown()) then return end
    local rows = dialog.shown.read()
    if rows then
        OpenDialog(dialog.shown, rows)
    else
        dialog:Hide()
    end
end

-- The page's buttons and theme line belong to one RestedXP profile too. With the
-- module off the page is its header alone, which holds neither, but can hold the
-- note of a refused reload, so it rebuilds only when there is a note to show.
local function OnProfileChange()
    ShowCurrentRows()
    if KE.db.profile.SkinRestedXP.Enabled == true or Setup.StartNote() then RebuildPage() end
end

-- A click may come long after the preview opened, so it acts only on the profile
-- and rows on screen, and only when RestedXP's profile has a name to tie the change
-- to, whether it writes live or after a reload. A client can refuse a reload asked
-- for after other work has run, so the reload is asked for before the dialog closes
-- and the rows are saved; it runs when this click's code ends. Only the checks that
-- the change can be kept come first: the profile's name, then both addons loading
-- next time.
local function Confirm()
    local shown = dialog.shown
    local rows = shown.read()
    if not Rules.PreviewHolds(rows, Setup.Profile(), dialog.profile, dialog.rows) then
        ShowCurrentRows()
        return
    end
    if not Setup.CanSave() then
        dialog:Hide()
        Setup.NoProfile()
        return
    end
    if rows.reload == true then
        if not Setup.WillLoadNext() then
            dialog:Hide()
            Setup.NotLoading()
            return
        end
        KE:ReloadUI()
        dialog:Hide()
        Setup.SavePending(shown.kind, rows)
        return
    end
    dialog:Hide()
    shown.write(rows)
    Look.ReloadOrAsk()
    RebuildPage()
end

local function DialogText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY")
    KE:ApplyThemeFont(text, "normal")
    text:SetJustifyH("LEFT")
    return text
end

local function BuildDialog()
    local f = CreateFrame("Frame", "KitnEssentialsRestedXPSetupDialog", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetWidth(DIALOG_WIDTH)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(Theme.bgMedium[1], Theme.bgMedium[2], Theme.bgMedium[3], 1)
    f:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
    local inner = DIALOG_WIDTH - DIALOG_PAD * 2
    f.title = DialogText(f)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", DIALOG_PAD, -DIALOG_PAD)
    f.title:SetWidth(inner)
    f.body = DialogText(f)
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -DIALOG_GAP)
    f.body:SetWidth(inner)
    f.cells = {}
    for rowIndex = 0, MAX_ROWS do
        f.cells[rowIndex] = {}
        for column, x in ipairs(COLUMNS) do
            local cell = DialogText(f)
            cell:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", x, -DIALOG_GAP - rowIndex * DIALOG_ROW)
            f.cells[rowIndex][column] = cell
        end
    end
    f.cells[0][1]:SetText("RestedXP setting")
    f.cells[0][2]:SetText("Now")
    f.cells[0][3]:SetText("After")
    f.note = DialogText(f)
    f.note:SetWidth(inner)
    f.confirm = GUIFrame:CreateButton(f, "Change", {
        height = BUTTON_H,
        callback = Confirm,
    })
    f.confirm:SetSize(BUTTON_W, BUTTON_H)
    f.confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -DIALOG_PAD, DIALOG_PAD)
    f.cancel = GUIFrame:CreateButton(f, "Cancel", {
        height = BUTTON_H,
        callback = function() f:Hide() end,
    })
    f.cancel:SetSize(BUTTON_W, BUTTON_H)
    f.cancel:SetPoint("RIGHT", f.confirm, "LEFT", -DIALOG_GAP, 0)
    return f
end

local function ShowValue(value)
    if value == true then return "On" end
    if value == false or value == nil then return "Off" end
    return tostring(value)
end

function OpenDialog(shown, rows)
    dialog = dialog or BuildDialog()
    Setup.WatchProfile(OnProfileChange)
    dialog.shown, dialog.rows, dialog.profile = shown, rows, Setup.Profile()
    dialog.title:SetText(KE:ColorTextByTheme(shown.title))
    dialog.body:SetText(shown.body)
    for rowIndex = 1, MAX_ROWS do
        local row, cells = rows[rowIndex], dialog.cells[rowIndex]
        cells[1]:SetText(row and row.label or "")
        cells[2]:SetText(row and ShowValue(row.now) or "")
        cells[3]:SetText(row and ShowValue(row.after) or "")
    end
    local tableHeight = (#rows + 1) * DIALOG_ROW
    dialog.note:ClearAllPoints()
    dialog.note:SetPoint("TOPLEFT", dialog.body, "BOTTOMLEFT", 0, -DIALOG_GAP * 2 - tableHeight)
    dialog.note:SetText(rows.reload and TEXT_RELOAD_NOTE or "")
    dialog.confirm.text:SetText(rows.reload and "Change and Reload" or "Change")
    dialog:SetHeight(DIALOG_PAD * 2 + dialog.title:GetStringHeight() + dialog.body:GetStringHeight()
        + tableHeight + (rows.reload and dialog.note:GetStringHeight() or 0) + DIALOG_GAP * 4 + BUTTON_H)
    dialog:Show()
end

-- A Beta or V2 change waits for RestedXP's next start, and after this load's start
-- was missed the next one most likely is too, so such rows count as none.
local function Rows(rows)
    if not (rows and #rows > 0) then return nil end
    if rows.reload and Setup.StartMissed() then return nil end
    return rows
end

local SETUP_DIALOG = {
    kind = "setup",
    title = TEXT_SETUP_TITLE,
    body = TEXT_SETUP_BODY,
    read = function() return Setup.MayWrite() and Rows(Setup.Plan()) or nil end,
    write = Setup.Write,
}

-- No module test: the switch turning off is what opens this one.
local UNDO_DIALOG = {
    kind = "undo",
    title = TEXT_UNDO_TITLE,
    body = TEXT_UNDO_BODY,
    read = function() return Rows(Setup.Undo()) end,
    write = Setup.WriteUndo,
}

local function OpenSetup()
    local rows = SETUP_DIALOG.read()
    if rows then OpenDialog(SETUP_DIALOG, rows) end
end

local function OpenUndo()
    local rows = UNDO_DIALOG.read()
    if rows then OpenDialog(UNDO_DIALOG, rows) end
end

---------------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------------
local function ApplyModuleState(enabled)
    local mod = GetModule()
    if not mod then return end
    mod.db.Enabled = enabled
    if enabled then
        KitnEssentials:EnableModule(PAGE_ID)
        return
    end
    KitnEssentials:DisableModule(PAGE_ID)
    mod:AskIconsBack()
    local undo = Setup.Undo()
    if undo and undo.reload then OpenUndo() end
end

local function BuildHeader(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SkinRestedXP
    if not db then return yOffset, true end

    local installed = Installed()
    local card = GUIFrame:CreateCard(scrollChild, "RestedXP", yOffset)
    card:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)
    card:AddLabel("Gives " .. KE:Gold("RestedXP Guides") .. " the KitnEssentials look: its colors, its text under " ..
        "RestedXP's arrow, step icons, and an optional single guide window.\n\nNeeds " ..
        KE:Gold("RestedXP Guides") .. ". " ..
        (installed and ("It changes RestedXP's settings when you click, after showing you what changes, and for " ..
            "a new character only if you turn on " .. KE:Gold("Set Up New Characters") .. ". Turning this off " ..
            "puts RestedXP's theme back.")
            or "Nothing here works until it is installed."))
    -- With the module off too: a waiting Undo runs at the start without it.
    local startNote = Setup.StartNote()
    if startNote then
        card:AddNote(startNote)
        Setup.ReportStart()
    end
    card:SetEnabled(installed)
    return card:GetNextOffset(), db.Enabled ~= true
end

---------------------------------------------------------------------------------
-- General tab
---------------------------------------------------------------------------------
local function V2Status()
    local v2 = Safe.Dig(_G.RXP, "v2")
    if not Safe.Has(v2, "IsGuideWindowEnabled") then return "Not available" end
    local on = Safe.Run("PageV2", v2.IsGuideWindowEnabled, v2)
    return on and "On" or "Off. KE's guide window needs it"
end

local function AddThisCharacter(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    Setup.WatchProfile(OnProfileChange)
    manager:SetCondition("planReady", function() return SETUP_DIALOG.read() ~= nil end)
    manager:SetCondition("hasRecord", function() return UNDO_DIALOG.read() ~= nil end)

    local card = GUIFrame:CreateCard(scrollChild, "This Character", yOffset)
    manager:Register(card, "all")

    local version = C_AddOns.GetAddOnMetadata(RXP_ADDON, "Version")
    local found = Installed() and ("Found" .. (version and (", v" .. version) or "")) or "Not installed"
    local profile = Setup.Profile()
    card:AddLabel("RestedXP Guides: " .. found)
    card:AddLabel("V2 interface, this character: " .. V2Status())
    card:AddLabel("RestedXP theme: " .. tostring(profile and profile.activeTheme or "Not available"))

    local buttonRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local setupButton = GUIFrame:CreateButton(buttonRow, "Set Up This Character", {
        height = BUTTON_H,
        callback = OpenSetup,
    })
    buttonRow:AddWidget(setupButton, 1 / 2)
    manager:Register(setupButton, "planReady")
    local undoButton = GUIFrame:CreateButton(buttonRow, "Undo Setup", {
        height = BUTTON_H,
        callback = OpenUndo,
    })
    buttonRow:AddWidget(undoButton, 1 / 2)
    manager:Register(undoButton, "hasRecord")
    card:AddRow(buttonRow, Theme.rowHeight)

    local switchRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local newCharacters = GUIFrame:CreateCheckbox(switchRow, "Set Up New Characters", {
        value = db.SetUpNewCharacters == true,
        callback = function(checked)
            db.SetUpNewCharacters = checked
            if checked then Setup.MarkSeen() end
        end,
    })
    switchRow:AddWidget(newCharacters, 1)
    manager:Register(newCharacters, "all")
    card:AddRow(switchRow, Theme.rowHeight)

    card:AddLabel("Off to start. On: a character KE has not seen gets the changes above as it first loads, with " ..
        "no reload. RestedXP keeps these per character unless you share a profile.")
    for _, part in ipairs(PART_LABELS) do
        if not Safe.PartOn(part.key) then card:AddNote(part.label .. TEXT_REASON) end
    end
    return card:GetNextOffset()
end

local function PaletteOptions()
    local options = { { key = "ke", text = "KE, Follow the Accent" } }
    for _, key in ipairs(Rules.PALETTE_ORDER) do
        options[#options + 1] = { key = key, text = Rules.PALETTES[key].name }
    end
    return options
end

local function AddGuideLook(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    manager:SetCondition("kePalette", function() return db.Palette == "ke" end)
    manager:SetCondition("fullPalette", function() return db.Palette ~= "ke" end)

    local card = GUIFrame:CreateCard(scrollChild, "Guide Look", yOffset)
    manager:Register(card, "all")

    local lookRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local lookDrop = GUIFrame:CreateDropdown(lookRow, "Look", {
        options = LOOK_OPTIONS,
        value = db.Look or "window",
        callback = function(key)
            db.Look = key
            if page.module then page.module:LookChanged() end
            OpenSetup()
            RebuildPage()
        end,
    })
    lookRow:AddWidget(lookDrop, 1 / 2)
    manager:Register(lookDrop, "all")
    local paletteDrop = GUIFrame:CreateDropdown(lookRow, "Palette", {
        options = PaletteOptions(),
        value = db.Palette or "ke",
        callback = function(key)
            db.Palette = key
            if key == "ke" then db.AccentPreset = nil end
            page.ThemeChanged()
            RebuildPage()
        end,
    })
    lookRow:AddWidget(paletteDrop, 1 / 2)
    manager:Register(paletteDrop, "all")
    card:AddRow(lookRow, Theme.rowHeight)

    card:AddLabel("Accent")
    local accentRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local swatches = GUIFrame:CreatePresetSwatches(accentRow, {
        value = db.AccentPreset,
        callback = function(name)
            db.AccentPreset = name
            page.ThemeChanged()
        end,
    })
    accentRow:AddWidget(swatches, 1)
    manager:Register(swatches, "kePalette")
    card:AddRow(accentRow, Theme.rowHeight)

    local followRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local follow = GUIFrame:CreateCheckbox(followRow, "Backdrop and Highlights Follow the Palette", {
        value = db.FollowPalette ~= false,
        callback = function(checked)
            db.FollowPalette = checked
            page.ThemeChanged()
        end,
    })
    followRow:AddWidget(follow, 1)
    manager:Register(follow, "fullPalette")
    card:AddRow(followRow, Theme.rowHeight)

    card:AddLabel("The other looks: RestedXP's Own, and KE Colors on RestedXP's Windows. The accent follows " ..
        "KitnEssentials until you pick one. The switch matters once you pick a full palette such as Forest: on, the " ..
        "whole window takes its colors; off, the backdrop, borders and highlights stay KE's and only the accent and " ..
        "text change. A theme change waits for combat to end.")
    return card:GetNextOffset()
end

local function AddStepIcons(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    manager:SetCondition("iconStyle", function() return db.Look ~= "own" end)

    local card = GUIFrame:CreateCard(scrollChild, "Step Icons", yOffset)
    manager:Register(card, "all")
    local row = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local drop = GUIFrame:CreateDropdown(row, "Icon Style", {
        options = ICON_OPTIONS,
        value = db.IconStyle or "ke",
        callback = function(key) db.IconStyle = key end,
    })
    row:AddWidget(drop, 1)
    manager:Register(drop, "iconStyle")
    card:AddRow(row, Theme.rowHeight)
    card:AddLabel("Takes a reload, because RestedXP builds its rows from the icons as a guide loads. The other " ..
        "choice is RestedXP's Own.")
    return card:GetNextOffset()
end

local function BuildGeneralTab(scrollChild, yOffset, page)
    yOffset = AddThisCharacter(scrollChild, yOffset, page)
    yOffset = AddGuideLook(scrollChild, yOffset, page)
    return AddStepIcons(scrollChild, yOffset, page)
end

---------------------------------------------------------------------------------
-- Page registration
---------------------------------------------------------------------------------
-- Each tab makes its own manager. The host builds a tab only while the module is
-- on, so no manager spans two builders. gate grays a whole tab.
local function TabPage(getBuilder, gate)
    return function(scrollChild, yOffset)
        local db = KE.db and KE.db.profile.SkinRestedXP
        if not db then return yOffset end
        local manager = GUIFrame:CreateWidgetStateManager()
        local mod = GetModule()
        local page = { db = db, manager = manager, module = mod }

        function page.Refresh()
            manager:UpdateAll(db.Enabled == true and Installed() and (not gate or gate(db)))
        end
        function page.Apply()
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
        function page.ThemeChanged()
            if mod then mod:ThemeChanged() end
        end
        function page.Setter(key)
            return function(value)
                db[key] = value
                page.Apply()
                page.Refresh()
            end
        end
        function page.Separator(card)
            local row = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
            local separator = GUIFrame:CreateSeparator(row)
            row:AddWidget(separator, 1)
            manager:Register(separator, "all")
            card:AddRow(row, Theme.rowHeightSeparator)
        end

        yOffset = getBuilder()(scrollChild, yOffset, page)
        page.Refresh()
        return yOffset
    end
end

GUIFrame:RegisterContent(TAB_GENERAL, TabPage(function() return BuildGeneralTab end))
GUIFrame:RegisterContent(TAB_ARROW, TabPage(function() return GUIFrame.RestedXPTabs.Arrow end))
GUIFrame:RegisterContent(TAB_WINDOW, TabPage(function() return GUIFrame.RestedXPTabs.Window end,
    function(db) return db.Look == "window" end))

GUIFrame:RegisterTabbedContent(PAGE_ID, {
    { id = TAB_GENERAL, label = "General" },
    { id = TAB_ARROW, label = "Arrow" },
    { id = TAB_WINDOW, label = "Guide Window" },
}, {
    headerBuilder = BuildHeader,
})
