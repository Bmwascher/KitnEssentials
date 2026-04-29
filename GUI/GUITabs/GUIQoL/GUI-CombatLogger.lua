-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatLogger.lua                                    ║
-- ║  GUI: Combat Logger                                      ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           CombatLogger module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("CombatLogger", true)
    end
    return nil
end

GUIFrame:RegisterContent("CombatLogger", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatLogger
    if not db then return yOffset end

    local CL = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if CL and CL.ApplySettings then CL:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not CL then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("CombatLogger")
        else KitnEssentials:DisableModule("CombatLogger") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Logger", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Logger", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Combat Logger",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 70)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Automatically enables combat logging for selected content types.\n" ..
        KE:ColorTextByTheme("-") .. " Requires " .. KE:ColorTextByTheme("Advanced Combat Logging") .. " CVar enabled for Warcraft Logs.\n" ..
        "   You will be prompted to enable it on login if it is disabled.",
        70, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 70, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Settings", yOffset)
    manager:Register(card2, "all")

    local settingsDefs = {
        { key = "DelayStop", label = "Delay Stop", desc = "Wait 30s before stopping log after leaving instance. (Warcraft Recorder)", default = true },
        { key = "DisableACLPrompt", label = "Disable ACL Prompt", desc = "Hide the login popup to enable Advanced Combat Logging.", default = false },
        { key = "QuietMode", label = "Quiet Mode", desc = "Suppress chat messages when logging starts/stops.", default = false },
    }

    for i, def in ipairs(settingsDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local label = def.label .. "  |cff888888- " .. def.desc .. "|r"
        local isLast = i == #settingsDefs
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card2.content, rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, label, {
            value = checked,
            callback = function(val) db[def.key] = val end,
        })
        row:AddWidget(checkbox, 1)
        manager:Register(checkbox, "all")
        if isLast then
            card2:AddRow(row, rowHeight, 0)
        else
            card2:AddRow(row, rowHeight)
        end
    end

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Dungeons
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Dungeons", yOffset)
    manager:Register(card3, "all")

    local dungeonDefs = {
        { key = "DungeonNormal", label = "Normal" },
        { key = "DungeonHeroic", label = "Heroic" },
        { key = "DungeonMythic", label = "Mythic" },
        { key = "DungeonMythicPlus", label = "Mythic+" },
        { key = "DungeonTimewalking", label = "Timewalking" },
    }

    local dungeonRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    for _, def in ipairs(dungeonDefs) do
        local checkbox = GUIFrame:CreateCheckbox(dungeonRow, def.label, {
            value = db[def.key] == true,
            callback = function(val) db[def.key] = val; ApplySettings() end,
        })
        dungeonRow:AddWidget(checkbox, 1 / #dungeonDefs)
        manager:Register(checkbox, "all")
    end
    card3:AddRow(dungeonRow, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Raids
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Raids", yOffset)
    manager:Register(card4, "all")

    local raidDefs = {
        { key = "RaidLFR", label = "LFR" },
        { key = "RaidNormal", label = "Normal" },
        { key = "RaidHeroic", label = "Heroic" },
        { key = "RaidMythic", label = "Mythic" },
        { key = "RaidTimewalking", label = "Timewalking" },
    }

    local raidRow = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    for _, def in ipairs(raidDefs) do
        local checkbox = GUIFrame:CreateCheckbox(raidRow, def.label, {
            value = db[def.key] == true,
            callback = function(val) db[def.key] = val; ApplySettings() end,
        })
        raidRow:AddWidget(checkbox, 1 / #raidDefs)
        manager:Register(checkbox, "all")
    end
    card4:AddRow(raidRow, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: PvP & Other
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "PvP & Other", yOffset)
    manager:Register(card5, "all")

    -- Grouped 3-2-2: casual PvP/PvE | rated | practice/social.
    local pvpRows = {
        { { key = "PvPRegularBG", label = "Regular BG" },
          { key = "PvPSoloShuffle", label = "Solo Shuffle" },
          { key = "ScenarioTorghast", label = "Torghast" } },
        { { key = "PvPRatedBG", label = "Rated BG" },
          { key = "PvPRatedArena", label = "Rated Arena" } },
        { { key = "PvPWarGame", label = "War Game" },
          { key = "PvPArenaSkirmish", label = "Arena Skirmish" } },
    }

    for i, defs in ipairs(pvpRows) do
        local isLast = i == #pvpRows
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card5.content, rowHeight)
        for _, def in ipairs(defs) do
            local checkbox = GUIFrame:CreateCheckbox(row, def.label, {
                value = db[def.key] == true,
                callback = function(val) db[def.key] = val; ApplySettings() end,
            })
            row:AddWidget(checkbox, 1/3)
            manager:Register(checkbox, "all")
        end
        if isLast then
            card5:AddRow(row, rowHeight, 0)
        else
            card5:AddRow(row, rowHeight)
        end
    end

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
