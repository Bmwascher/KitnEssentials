-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs

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
    local allWidgets = {}

    local function ApplySettings()
        if CL and CL.ApplySettings then CL:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not CL then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("CombatLogger")
        else KitnEssentials:DisableModule("CombatLogger") end
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
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Logger", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Logger", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Combat Logger", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    local noteHeight = 70
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Automatically enables combat logging for selected content types.\n" ..
        KE:ColorTextByTheme("-") .. " Requires " .. KE:ColorTextByTheme("Advanced Combat Logging") .. " CVar enabled for Warcraft Logs.\n" ..
        "   You will be prompted to enable it on login if it is disabled.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Settings", yOffset)
    table_insert(allWidgets, card2)

    local settingsDefs = {
        { key = "DelayStop", label = "Delay Stop", desc = "Wait 30s before stopping log after leaving instance. (Warcraft Recorder)", default = true },
        { key = "DisableACLPrompt", label = "Disable ACL Prompt", desc = "Hide the login popup to enable Advanced Combat Logging.", default = false },
        { key = "QuietMode", label = "Quiet Mode", desc = "Suppress chat messages when logging starts/stops.", default = false },
    }

    for _, def in ipairs(settingsDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local label = def.label .. "  |cff888888- " .. def.desc .. "|r"
        local row = GUIFrame:CreateRow(card2.content, 38)
        local checkbox = GUIFrame:CreateCheckbox(row, label, checked,
            function(val) db[def.key] = val end)
        row:AddWidget(checkbox, 1)
        table_insert(allWidgets, checkbox)
        card2:AddRow(row, 38)
    end

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Dungeons
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Dungeons", yOffset)
    table_insert(allWidgets, card3)

    local dungeonDefs = {
        { key = "DungeonNormal", label = "Normal" },
        { key = "DungeonHeroic", label = "Heroic" },
        { key = "DungeonMythic", label = "Mythic" },
        { key = "DungeonMythicPlus", label = "Mythic+" },
        { key = "DungeonTimewalking", label = "Timewalking" },
    }

    local dungeonRow = GUIFrame:CreateRow(card3.content, 38)
    for _, def in ipairs(dungeonDefs) do
        local checked = db[def.key] == true
        local checkbox = GUIFrame:CreateCheckbox(dungeonRow, def.label, checked,
            function(val) db[def.key] = val; ApplySettings() end)
        dungeonRow:AddWidget(checkbox, 1 / #dungeonDefs)
        table_insert(allWidgets, checkbox)
    end
    card3:AddRow(dungeonRow, 38)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Raids
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Raids", yOffset)
    table_insert(allWidgets, card4)

    local raidDefs = {
        { key = "RaidLFR", label = "LFR" },
        { key = "RaidNormal", label = "Normal" },
        { key = "RaidHeroic", label = "Heroic" },
        { key = "RaidMythic", label = "Mythic" },
        { key = "RaidTimewalking", label = "Timewalking" },
    }

    local raidRow = GUIFrame:CreateRow(card4.content, 38)
    for _, def in ipairs(raidDefs) do
        local checked = db[def.key] == true
        local checkbox = GUIFrame:CreateCheckbox(raidRow, def.label, checked,
            function(val) db[def.key] = val; ApplySettings() end)
        raidRow:AddWidget(checkbox, 1 / #raidDefs)
        table_insert(allWidgets, checkbox)
    end
    card4:AddRow(raidRow, 38)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: PvP & Other
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "PvP & Other", yOffset)
    table_insert(allWidgets, card5)

    -- Row 1: Regular BG | Solo Shuffle | Torghast
    local pvpRow1 = GUIFrame:CreateRow(card5.content, 38)
    local regBGCheck = GUIFrame:CreateCheckbox(pvpRow1, "Regular BG", db.PvPRegularBG == true,
        function(val) db.PvPRegularBG = val; ApplySettings() end)
    pvpRow1:AddWidget(regBGCheck, 1 / 3)
    table_insert(allWidgets, regBGCheck)

    local soloShuffleCheck = GUIFrame:CreateCheckbox(pvpRow1, "Solo Shuffle", db.PvPSoloShuffle == true,
        function(val) db.PvPSoloShuffle = val; ApplySettings() end)
    pvpRow1:AddWidget(soloShuffleCheck, 1 / 3)
    table_insert(allWidgets, soloShuffleCheck)

    local torghastCheck = GUIFrame:CreateCheckbox(pvpRow1, "Torghast", db.ScenarioTorghast == true,
        function(val) db.ScenarioTorghast = val; ApplySettings() end)
    pvpRow1:AddWidget(torghastCheck, 1 / 3)
    table_insert(allWidgets, torghastCheck)
    card5:AddRow(pvpRow1, 38)

    -- Row 2: Rated BG | Rated Arena
    local pvpRow2 = GUIFrame:CreateRow(card5.content, 38)
    local ratedBGCheck = GUIFrame:CreateCheckbox(pvpRow2, "Rated BG", db.PvPRatedBG == true,
        function(val) db.PvPRatedBG = val; ApplySettings() end)
    pvpRow2:AddWidget(ratedBGCheck, 1 / 3)
    table_insert(allWidgets, ratedBGCheck)

    local ratedArenaCheck = GUIFrame:CreateCheckbox(pvpRow2, "Rated Arena", db.PvPRatedArena == true,
        function(val) db.PvPRatedArena = val; ApplySettings() end)
    pvpRow2:AddWidget(ratedArenaCheck, 1 / 3)
    table_insert(allWidgets, ratedArenaCheck)
    card5:AddRow(pvpRow2, 38)

    -- Row 3: War Game | Arena Skirmish
    local pvpRow3 = GUIFrame:CreateRow(card5.content, 38)
    local warGameCheck = GUIFrame:CreateCheckbox(pvpRow3, "War Game", db.PvPWarGame == true,
        function(val) db.PvPWarGame = val; ApplySettings() end)
    pvpRow3:AddWidget(warGameCheck, 1 / 3)
    table_insert(allWidgets, warGameCheck)

    local skirmishCheck = GUIFrame:CreateCheckbox(pvpRow3, "Arena Skirmish", db.PvPArenaSkirmish == true,
        function(val) db.PvPArenaSkirmish = val; ApplySettings() end)
    pvpRow3:AddWidget(skirmishCheck, 1 / 3)
    table_insert(allWidgets, skirmishCheck)
    card5:AddRow(pvpRow3, 38)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
