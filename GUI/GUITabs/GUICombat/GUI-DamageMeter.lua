-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DamageMeter.lua                                     ║
-- ║  GUI: Damage Meter                                       ║
-- ║  Purpose: Configuration panel for the DamageMeter module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local activeTab = "General"

-- Resolves the live module handle (may be nil very early in load).
local function GetDM()
    return KitnEssentials and KitnEssentials:GetModule("DamageMeter", true)
end

-- Applies live config changes through the module's single apply path.
local function ApplySettings()
    local DM = GetDM()
    if DM and DM.ApplySettings then DM:ApplySettings() end
end

-- Schedules a full page rebuild on the next frame (used by the Windows tab's
-- Configure-For context switches and arrangement changes that change which
-- widgets appear). Defined here; first consumed when the Windows tab lands.
local function RebuildPage()
    if GUIFrame.RefreshContent then
        C_Timer.After(0, function() GUIFrame:RefreshContent() end)
    end
end

---------------------------------------------------------------------------------
-- General tab
---------------------------------------------------------------------------------
local function BuildGeneralTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("DamageMeter", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DamageMeter")
        else
            KitnEssentials:DisableModule("DamageMeter")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Damage Meter", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Damage Meter", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            manager:UpdateAll(db.Enabled ~= false)
        end,
        msgPopup = true,
        msgText = "Damage Meter",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " In-client meter built on Blizzard's 12.0 damage-meter data.\n" ..
        KE:ColorTextByTheme("-") .. " Switch type/segment on the meter itself; the GUI sets defaults & look.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Behavior toggles (Replace Blizzard, Lock dock)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Behavior", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local replaceCheck = GUIFrame:CreateCheckbox(row2a, "Replace Blizzard Meter", {
        value = db.ReplaceBlizzard ~= false,
        callback = function(checked)
            db.ReplaceBlizzard = checked
            if DM and DM.ApplyReplaceBlizzard then DM:ApplyReplaceBlizzard() end
        end,
    })
    row2a:AddWidget(replaceCheck, 0.5)
    manager:Register(replaceCheck, "all")

    local lockCheck = GUIFrame:CreateCheckbox(row2a, "Lock Dock", {
        value = db.Locked == true,
        callback = function(checked)
            db.Locked = checked
            if DM and DM.ApplyLockState then DM:ApplyLockState() end
        end,
    })
    row2a:AddWidget(lockCheck, 0.5)
    manager:Register(lockCheck, "all")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings (the dock is the positioned frame)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = "Position",
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    local dragNoteCard = GUIFrame:CreateCard(scrollChild, "Tip", yOffset)
    manager:Register(dragNoteCard, "all")
    local dnRow = GUIFrame:CreateRow(dragNoteCard.content, Theme.rowHeightLast)
    local dnText = GUIFrame:CreateText(dnRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Drag the dock in " .. KE:ColorTextByTheme("/kes edit") ..
        " (disabled while locked). Resize panes by dragging the gaps between windows.\n" ..
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("/kedm") ..
        " toggles the dock; " .. KE:ColorTextByTheme("/kedm reset") .. " clears all segments.",
        Theme.rowHeightLast, "hide")
    dnRow:AddWidget(dnText, 1)
    manager:Register(dnText, "all")
    dragNoteCard:AddRow(dnRow, Theme.rowHeightLast, 0)
    yOffset = dragNoteCard:GetNextOffset()

    return yOffset
end

---------------------------------------------------------------------------------
-- Page registration
---------------------------------------------------------------------------------
GUIFrame:RegisterContent("DamageMeter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DamageMeter
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "General", label = "General" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
