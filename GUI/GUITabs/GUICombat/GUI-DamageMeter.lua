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

-- Ordered option lists for the per-context default-display rows.
local METER_TYPE_OPTIONS = {
    { key = Enum.DamageMeterType.DamageDone,  text = "Damage Done" },
    { key = Enum.DamageMeterType.HealingDone, text = "Healing Done" },
    { key = Enum.DamageMeterType.DamageTaken, text = "Damage Taken" },
    { key = Enum.DamageMeterType.Interrupts,  text = "Interrupts" },
    { key = Enum.DamageMeterType.Dispels,     text = "Dispels" },
    { key = Enum.DamageMeterType.Deaths,      text = "Deaths" },
}

local SEGMENT_OPTIONS = {
    { key = Enum.DamageMeterSessionType.Current, text = "Current" },
    { key = Enum.DamageMeterSessionType.Overall, text = "Overall" },
}

local CONTEXT_OPTIONS = {
    { key = "Default",      text = "Default" },
    { key = "Dungeon",      text = "Dungeon" },
    { key = "Mythic+",      text = "Mythic+" },
    { key = "Raid",         text = "Raid" },
    { key = "Arena",        text = "Arena" },
    { key = "Battleground", text = "Battleground" },
    { key = "Scenario",     text = "Scenario" },
}

local ARRANGEMENT_OPTIONS = {
    { key = "Horizontal", text = "Horizontal" },
    { key = "Vertical",   text = "Vertical" },
    { key = "Custom",     text = "Custom" },
}

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
-- Windows tab (structure + per-context defaults)
---------------------------------------------------------------------------------
local function BuildWindowsTab(scrollChild, yOffset, db, manager)
    local DM = GetDM()

    -- Stable list of referenced window indices, in dock order.
    local winList = {}
    if DM and DM.DockWindowIndices then
        local found = DM:DockWindowIndices({})
        for i = 1, #found do winList[i] = found[i] end
    end

    local arrangement = (DM and DM.GetArrangement and DM:GetArrangement()) or "Custom"
    local numCols = (db.Dock and db.Dock.Columns and #db.Dock.Columns) or 1

    ----------------------------------------------------------------
    -- Card 1: Arrangement
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Arrangement", yOffset)
    manager:Register(card1, "all")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local arrDropdown = GUIFrame:CreateDropdown(row1, "Layout", {
        options = ARRANGEMENT_OPTIONS,
        value = arrangement,
        callback = function(key)
            if DM and DM.SetArrangement then
                DM:SetArrangement(key)
            end
            RebuildPage()
        end,
    })
    row1:AddWidget(arrDropdown, 0.5)
    manager:Register(arrDropdown, "all")

    local maxWin = db.MaxWindows or 5
    local addBtn = GUIFrame:CreateButton(row1, "Add Window", {
        callback = function()
            if DM and DM.AddWindow then DM:AddWindow() end
            RebuildPage()
        end,
    })
    row1:AddWidget(addBtn, 0.25)
    manager:Register(addBtn, "all")

    local removeBtn = GUIFrame:CreateButton(row1, "Remove Window", {
        callback = function()
            -- Remove the highest referenced index (the most recently added).
            if DM and DM.RemoveWindow and #winList > 1 then
                DM:RemoveWindow(winList[#winList])
            end
            RebuildPage()
        end,
    })
    row1:AddWidget(removeBtn, 0.25)
    manager:Register(removeBtn, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local arrNoteRow = GUIFrame:CreateRow(card1.content, 50)
    local arrNote = GUIFrame:CreateText(arrNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " " .. KE:ColorTextByTheme("Horizontal") .. ": one window per column · " ..
        KE:ColorTextByTheme("Vertical") .. ": all stacked · " .. KE:ColorTextByTheme("Custom") .. ": assign columns below.\n" ..
        KE:ColorTextByTheme("-") .. " Resize the split between windows by dragging the gap in the world (up to " ..
        maxWin .. " windows).",
        50, "hide")
    arrNoteRow:AddWidget(arrNote, 1)
    manager:Register(arrNote, "all")
    card1:AddRow(arrNoteRow, 50, 0)

    -- Custom mode: per-window column pickers.
    if arrangement == "Custom" and #winList > 0 then
        for n = 1, #winList do
            local idx = winList[n]
            -- Which column currently holds this window?
            local curCol = 1
            if db.Dock and db.Dock.Columns then
                for c = 1, #db.Dock.Columns do
                    local wins = db.Dock.Columns[c].Windows
                    if wins then
                        for r = 1, #wins do
                            if wins[r] == idx then curCol = c; break end
                        end
                    end
                end
            end
            local colOpts = {}
            for c = 1, numCols do colOpts[c] = { key = c, text = "Column " .. c } end
            local rowC = GUIFrame:CreateRow(card1.content,
                (n == #winList) and Theme.rowHeightLast or Theme.rowHeight)
            local colDropdown = GUIFrame:CreateDropdown(rowC, "Window " .. idx .. " Column", {
                options = colOpts,
                value = curCol,
                callback = function(key)
                    if DM and DM.SetWindowColumn then DM:SetWindowColumn(idx, key) end
                    RebuildPage()
                end,
            })
            rowC:AddWidget(colDropdown, 1)
            manager:Register(colDropdown, "all")
            card1:AddRow(rowC, (n == #winList) and Theme.rowHeightLast or Theme.rowHeight,
                (n == #winList) and 0 or nil)
        end
    end

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Default Display (Configure For: <context>)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Default Display", yOffset)
    manager:Register(card2, "all")

    -- Transient (not saved) context the rows below edit; survives the rebuild.
    if DM and DM.guiConfigContext == nil then DM.guiConfigContext = "Default" end
    local ctx = (DM and DM.guiConfigContext) or "Default"

    local rowCtx = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local ctxDropdown = GUIFrame:CreateDropdown(rowCtx, "Configure For", {
        options = CONTEXT_OPTIONS,
        value = ctx,
        callback = function(key)
            if DM then DM.guiConfigContext = key end
            RebuildPage()
        end,
    })
    rowCtx:AddWidget(ctxDropdown, 1)
    manager:Register(ctxDropdown, "all")
    card2:AddRow(rowCtx, Theme.rowHeight)

    local ctxNoteRow = GUIFrame:CreateRow(card2.content, 50)
    local ctxNote = GUIFrame:CreateText(ctxNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Defaults auto-apply when you enter that content. Unset contexts inherit Default.\n" ..
        KE:ColorTextByTheme("-") .. " Live type/segment changes on the meter stick until the content changes.",
        50, "hide")
    ctxNoteRow:AddWidget(ctxNote, 1)
    manager:Register(ctxNote, "all")
    card2:AddRow(ctxNoteRow, 50, 0)

    -- One row per window: Enabled · Type · Segment for the selected context.
    db.Windows = db.Windows or {}
    for n = 1, #winList do
        local idx = winList[n]
        local window = db.Windows[idx]
        if window and window.Contexts then
            -- Effective config: this context's entry, else Default.
            local cfg = window.Contexts[ctx] or window.Contexts.Default or {}

            -- Writer: ensures a Contexts[ctx] entry exists (seeded from Default),
            -- then sets one field. First edit of an inheriting context forks it.
            local function writeField(field, value)
                window.Contexts[ctx] = window.Contexts[ctx] or {
                    Enabled = (window.Contexts.Default and window.Contexts.Default.Enabled) ~= false,
                    MeterType = (window.Contexts.Default and window.Contexts.Default.MeterType)
                        or Enum.DamageMeterType.DamageDone,
                    SessionType = (window.Contexts.Default and window.Contexts.Default.SessionType)
                        or Enum.DamageMeterSessionType.Current,
                }
                window.Contexts[ctx][field] = value
                if DM and DM.RefreshDock then DM:RefreshDock() end
                if DM and DM.Tick then DM:Tick() end
            end

            local isLast = (n == #winList)
            local rowW = GUIFrame:CreateRow(card2.content, isLast and Theme.rowHeightLast or Theme.rowHeight)

            local enChk = GUIFrame:CreateCheckbox(rowW, "Window " .. idx, {
                value = cfg.Enabled ~= false,
                callback = function(checked) writeField("Enabled", checked) end,
            })
            rowW:AddWidget(enChk, 0.34)
            manager:Register(enChk, "all")

            local typeDd = GUIFrame:CreateDropdown(rowW, "Type", {
                options = METER_TYPE_OPTIONS,
                value = cfg.MeterType or Enum.DamageMeterType.DamageDone,
                callback = function(key) writeField("MeterType", key) end,
            })
            rowW:AddWidget(typeDd, 0.33)
            manager:Register(typeDd, "all")

            local segDd = GUIFrame:CreateDropdown(rowW, "Segment", {
                options = SEGMENT_OPTIONS,
                value = cfg.SessionType or Enum.DamageMeterSessionType.Current,
                callback = function(key) writeField("SessionType", key) end,
            })
            rowW:AddWidget(segDd, 0.33)
            manager:Register(segDd, "all")

            card2:AddRow(rowW, isLast and Theme.rowHeightLast or Theme.rowHeight, isLast and 0 or nil)
        end
    end

    yOffset = card2:GetNextOffset()
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
            { id = "Windows", label = "Windows" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Windows" then
        yOffset = BuildWindowsTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
