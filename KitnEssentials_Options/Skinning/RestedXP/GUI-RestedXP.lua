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
local ipairs, tostring, type = ipairs, tostring, type

local Safe, Rules, Setup, RxpTheme = KE.RestedXPSafe, KE.RestedXPRules, KE.RestedXPSetup, KE.RestedXPTheme
local Icons = KE.RestedXPIcons

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
local TEXT_OFF_NOTE = "Turn this off to put RestedXP back as it was."
local TEXT_NEW_CHARACTERS = "A character KE has not seen gets set up at the first load that can apply it, with no " ..
    "reload and no preview. Undo Setup puts it back."
local TEXT_WINDOW_HELD = "KE's guide window stays off until you answer the conflict prompt."
local TEXT_ICONS_WAIT = "KE's step icons come in at the next reload, because RestedXP builds its rows from them " ..
    "as a guide loads."

local DIALOG_WIDTH, DIALOG_PAD, DIALOG_ROW, DIALOG_GAP, BUTTON_H, BUTTON_W = 430, 14, 18, 10, 26, 150
local COLUMNS = { 0, 170, 290 }
local MAX_ROWS = 3
local GRAY_COLOR = { 0.66, 0.66, 0.66 }
local STATE_SHARE, STATE_BUTTON_Y = 0.72, -7
local NEW_CHARACTER_H, NEW_SWITCH_SHARE, NEW_SWITCH_RISE = 54, 0.1, 10

-- What each state of Rules.CharacterState says. window marks a line that tells of
-- KE's window, so the conflict prompt's line replaces it while that holds the window.
local CHARACTER_STATES = {
    notInstalled = {
        head = "Not installed",
        line = "Install RestedXP Guides first. Nothing here works until it is installed.",
    },
    notLoaded = {
        head = "Not loaded",
        line = "RestedXP Guides is off for this character. Turn it on in the AddOns list.",
    },
    noProfile = {
        head = "Not available",
        line = "RestedXP no longer has a call setup needs, so nothing can change here.",
    },
    reloading = {
        head = "Reload pending",
        line = "KE asked for a reload. If it does not come, this clears in two seconds.",
    },
    noWindow = {
        head = "Not available",
        line = "This RestedXP has no guide window KE can use, so KE's window can't start.",
    },
    notSetUp = {
        head = "Not set up", window = true,
        line = "One click and a reload turn on KE's guide window here.",
    },
    themeOnly = {
        head = "Not set up", window = true,
        line = "KE's guide window is on. One click, with no reload, adds KE's theme too.",
        lineLiveOff = "KE's guide window is on. One click and a reload add KE's theme too.",
    },
    setupMissed = {
        head = "Not set up",
        line = "RestedXP started before KitnEssentials at this load, so setup can't apply.",
    },
    setUp = {
        head = "Set up", good = true, window = true,
        line = "KE's guide window is on for this character.",
    },
    undoMissed = {
        head = "Set up", good = true,
        line = "RestedXP started before KitnEssentials at this load, so Undo can't apply.",
    },
    setUpFound = {
        head = "Set up", good = true, window = true,
        line = "KE's guide window is on. KE changed nothing here, so there is nothing to undo.",
    },
}

-- The Window and Setup parts have their own states.
local PART_LABELS = {
    { key = "Theme", label = "Theme" },
    { key = "Arrow", label = "Arrow" },
    { key = "Icons", label = "Step Icons" },
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

-- KE's card labels are white, so a secondary line sets its own gray.
local function Note(card, text)
    local label = card:AddLabel(text)
    label:SetTextColor(GRAY_COLOR[1], GRAY_COLOR[2], GRAY_COLOR[3], 1)
    return label
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

-- This Character's state and button belong to one RestedXP profile too. With the
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
        RebuildPage()
        return
    end
    dialog:Hide()
    shown.write(rows)
    RxpTheme.ReloadOrAsk()
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
        callback = function()
            Setup.MarkSeen()
            f:Hide()
            RebuildPage()
        end,
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

local function CharacterState()
    return Rules.CharacterState({
        installed = Installed(),
        loaded = C_AddOns.IsAddOnLoaded(RXP_ADDON) and type(_G.RXP) == "table",
        profile = Setup.Profile() ~= nil,
        window = Safe.PartOn("Window"),
        waiting = Setup.WaitingKind(),
        missed = Setup.StartMissed(),
        plan = Setup.Plan(),
        undo = Setup.Undo(),
    })
end

-- The button and turning the module on share this read, so a preview opens only where
-- the card lights the button.
local SETUP_DIALOG = {
    kind = "setup",
    title = TEXT_SETUP_TITLE,
    body = TEXT_SETUP_BODY,
    read = function()
        local _, which, live = CharacterState()
        return live and which == "setup" and Setup.MayWrite() and Setup.Plan() or nil
    end,
    write = Setup.Write,
}

-- No module test: the switch turning off is what opens this one.
local UNDO_DIALOG = {
    kind = "undo",
    title = TEXT_UNDO_TITLE,
    body = TEXT_UNDO_BODY,
    read = function()
        local rows = Setup.Undo()
        return Rules.Doable(rows, Setup.StartMissed()) and rows or nil
    end,
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
        -- The start marks the character seen, so a Cancel here stays canceled at the
        -- next login.
        KitnEssentials:EnableModule(PAGE_ID)
        OpenSetup()
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
    card:AddLabel("Gives " .. KE:Gold("RestedXP Guides") .. " KE's single guide window, icons and arrow text.")
    Note(card, installed and TEXT_OFF_NOTE
        or ("Needs " .. KE:Gold("RestedXP Guides") .. ". Nothing here works until it is installed."))
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
local function Colored(color, text)
    return "|cff" .. Rules.Hex(color) .. text .. "|r"
end

local function FoundLine()
    if not Installed() then return "RestedXP Guides not found" end
    local version = C_AddOns.GetAddOnMetadata(RXP_ADDON, "Version")
    return "RestedXP Guides " .. (version and (version .. " ") or "") .. "found"
end

local function AddThisCharacter(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager
    Setup.WatchProfile(OnProfileChange)
    manager:SetCondition("characterAction", function()
        local _, which, live = CharacterState()
        return live and (which == "undo" or Setup.MayWrite())
    end)

    local card = GUIFrame:CreateCard(scrollChild, "This Character", yOffset)
    manager:Register(card, "all")

    local key, which, live = CharacterState()
    local state = CHARACTER_STATES[key]
    local rival = KE:RestedXPRivalSettings()
    local line = state.window and rival and rival.rxpWindow == true and TEXT_WINDOW_HELD
        or RxpTheme.LiveReloadOff() and state.lineLiveOff or state.line
    local stateRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local stateBlock = GUIFrame:CreateText(stateRow, Colored(state.good and Theme.success or Theme.warning, state.head),
        Colored(GRAY_COLOR, line), Theme.rowHeight, "hide")
    stateRow:AddWidget(stateBlock, STATE_SHARE)
    manager:Register(stateBlock, "all")
    local button = GUIFrame:CreateButton(stateRow, which == "undo" and "Undo Setup" or "Set Up This Character", {
        height = BUTTON_H,
        callback = which == "undo" and OpenUndo or OpenSetup,
    })
    stateRow:AddWidget(button, 1 - STATE_SHARE, nil, 0, STATE_BUTTON_Y)
    button:SetFilled(live and which == "setup")
    manager:Register(button, "characterAction")
    card:AddRow(stateRow, Theme.rowHeight)

    for _, part in ipairs(PART_LABELS) do
        if not Safe.PartOn(part.key) then Note(card, part.label .. TEXT_REASON) end
    end
    if Setup.Profile() and Safe.PartOn("Icons") and not Icons.Applied() then Note(card, TEXT_ICONS_WAIT) end
    page.Separator(card)

    local newRow = GUIFrame:CreateRow(card.content, NEW_CHARACTER_H)
    local newCharacters = GUIFrame:CreateCheckbox(newRow, "", {
        value = db.SetUpNewCharacters ~= false,
        callback = function(checked)
            db.SetUpNewCharacters = checked
            Setup.MarkSeen()
            RebuildPage()
        end,
    })
    newRow:AddWidget(newCharacters, NEW_SWITCH_SHARE, nil, 0, NEW_SWITCH_RISE)
    manager:Register(newCharacters, "all")
    local newBlock = GUIFrame:CreateText(newRow, "Set Up New Characters", Colored(GRAY_COLOR, TEXT_NEW_CHARACTERS),
        NEW_CHARACTER_H, "hide")
    newRow:AddWidget(newBlock, 1 - NEW_SWITCH_SHARE)
    manager:Register(newBlock, "all")
    card:AddRow(newRow, NEW_CHARACTER_H)
    page.Separator(card)

    Note(card, FoundLine())
    return card:GetNextOffset()
end

local function BuildGeneralTab(scrollChild, yOffset, page)
    return AddThisCharacter(scrollChild, yOffset, page)
end

---------------------------------------------------------------------------------
-- Page registration
---------------------------------------------------------------------------------
-- Each tab makes its own manager. The host builds a tab only while the module is
-- on, so no manager spans two builders.
local function TabPage(getBuilder)
    return function(scrollChild, yOffset)
        local db = KE.db and KE.db.profile.SkinRestedXP
        if not db then return yOffset end
        local manager = GUIFrame:CreateWidgetStateManager()
        local mod = GetModule()
        local page = { db = db, manager = manager, module = mod }

        function page.Refresh()
            manager:UpdateAll(db.Enabled == true and Installed())
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
        page.Note = Note
        page.Rebuild = RebuildPage
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
GUIFrame:RegisterContent(TAB_WINDOW, TabPage(function() return GUIFrame.RestedXPTabs.Window end))

GUIFrame:RegisterTabbedContent(PAGE_ID, {
    { id = TAB_GENERAL, label = "General" },
    { id = TAB_ARROW, label = "Arrow" },
    { id = TAB_WINDOW, label = "Guide Window" },
}, {
    headerBuilder = BuildHeader,
})
