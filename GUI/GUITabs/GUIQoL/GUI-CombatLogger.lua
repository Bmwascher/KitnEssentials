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

-- The four lists live together so a change to one is made beside the others.
-- They are independent tables: nothing here stops the preset naming a key no
-- card offers.
local DUNGEONS = {
    { key = "DungeonNormal",      label = "Normal" },
    { key = "DungeonHeroic",      label = "Heroic" },
    { key = "DungeonMythic",      label = "Mythic" },
    { key = "DungeonMythicPlus",  label = "Mythic+" },
    { key = "DungeonTimewalking", label = "Timewalking" },
}

local RAIDS = {
    { key = "RaidLFR",         label = "LFR" },
    { key = "RaidNormal",      label = "Normal" },
    { key = "RaidHeroic",      label = "Heroic" },
    { key = "RaidMythic",      label = "Mythic" },
    { key = "RaidTimewalking", label = "Timewalking" },
}

local PVP = {
    { key = "PvPRatedArena",    label = "Rated Arena" },
    { key = "PvPSoloShuffle",   label = "Solo Shuffle" },
    { key = "PvPArenaSkirmish", label = "Skirmish" },
    { key = "PvPRatedBG",       label = "Rated BG" },
    { key = "PvPRegularBG",     label = "Battleground" },
    { key = "PvPWarGame",       label = "War Game" },
}

-- What Warcraft Recorder can record. Scenarios are absent on purpose: it does
-- not record delves or Torghast, so logging them would only grow the file.
-- Timewalking dungeons and war games are absent for the same reason.
local RECORDER_PRESET = {
    "DungeonMythicPlus", "DungeonMythic", "DungeonHeroic", "DungeonNormal",
    "RaidLFR", "RaidNormal", "RaidHeroic", "RaidMythic", "RaidTimewalking",
    "PvPRatedArena", "PvPSoloShuffle", "PvPArenaSkirmish",
    "PvPRatedBG", "PvPRegularBG",
}

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

    -- Every content card is the same grid, so it is written once.
    local function AddContentCard(title, defs, perRow)
        local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
        manager:Register(card, "all")

        local row
        for i, def in ipairs(defs) do
            -- Index at which the final row starts. A plain `#defs - perRow`
            -- only lands there when the last row is full, so a table whose
            -- count is not a multiple of perRow would give the row above the
            -- last one the last row's height and spacing.
            local isLastRow = i > #defs - ((#defs - 1) % perRow + 1)
            local rowHeight = isLastRow and Theme.rowHeightLast or Theme.rowHeight
            if not row then
                row = GUIFrame:CreateRow(card.content, rowHeight)
            end
            local checkbox = GUIFrame:CreateCheckbox(row, def.label, {
                value = db[def.key] == true,
                callback = function(val) db[def.key] = val; ApplySettings() end,
            })
            row:AddWidget(checkbox, 1 / perRow)
            manager:Register(checkbox, "all")

            if i % perRow == 0 or i == #defs then
                if isLastRow then
                    card:AddRow(row, rowHeight, 0)
                else
                    card:AddRow(row, rowHeight)
                end
                row = nil
            end
        end

        yOffset = card:GetNextOffset()
        return card
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Logger", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Combat Logger: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else,
    -- the label included.
    if db.Enabled == false then return card1:GetNextOffset() end

    card1:AddLabel("Turns the game's combat log on for the content you tick below, and " ..
        "off again when you leave." ..
        "\n\nThat log file is what |cffffd100Warcraft Logs|r uploads and what " ..
        "|cffffd100Warcraft Recorder|r reads to know when a pull, a key or a match starts " ..
        "and ends." ..
        "\n\nA log you started yourself with |cffffd100/combatlog|r is left alone - this " ..
        "only closes logs it opened.")

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Settings", yOffset)
    manager:Register(card2, "all")

    local settingsDefs = {
        { key = "DelayStop", label = "Delay Stop",
          desc = "Keep logging for 30 seconds after you leave, so the lines that close a recording still land.",
          default = true },
        { key = "PromptAdvanced", label = "Ask About Advanced Combat Logging",
          desc = "Offer to turn it on if it is off. Unticking only stops the question, not the logging.",
          default = true },
        { key = "QuietMode", label = "Quiet Mode",
          desc = "No chat line when logging starts or stops.",
          default = false },
    }

    for _, def in ipairs(settingsDefs) do
        local checked = db[def.key]
        if checked == nil then checked = def.default end
        local label = def.label .. "  |cff888888- " .. def.desc .. "|r"
        local row = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        local checkbox = GUIFrame:CreateCheckbox(row, label, {
            value = checked,
            callback = function(val) db[def.key] = val end,
        })
        row:AddWidget(checkbox, 1)
        manager:Register(checkbox, "all")
        card2:AddRow(row, Theme.rowHeight)
    end

    -- Read at build time, so the label is stale if the CVar changes while the
    -- page is open. Both button callbacks rebuild the page, which is what keeps
    -- it honest after a click.
    local advancedOn = false
    if CL and CL.IsAdvanced then advancedOn = CL:IsAdvanced() end

    local buttonRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)

    local advButton = GUIFrame:CreateButton(buttonRow,
        advancedOn and "Advanced Logging Is On" or "Turn On Advanced Logging", {
        width = 220,
        height = 28,
        tooltip = "Warcraft Logs requires this, and Warcraft Recorder needs it for detail. No reload.",
        callback = function()
            if CL and CL.EnableAdvanced then
                CL:EnableAdvanced()
                GUIFrame:RefreshContent()
            end
        end,
    })
    buttonRow:AddWidget(advButton, 1 / 2)
    manager:Register(advButton, "all")

    local presetButton = GUIFrame:CreateButton(buttonRow, "Warcraft Recorder Preset", {
        width = 220,
        height = 28,
        tooltip = "Tick every content type Warcraft Recorder can record, and turn on Advanced Combat Logging.",
        callback = function()
            for _, key in ipairs(RECORDER_PRESET) do
                db[key] = true
            end
            db.DelayStop = true
            if CL and CL.EnableAdvanced then
                CL:EnableAdvanced()
                ApplySettings()
            end
            GUIFrame:RefreshContent()
        end,
    })
    buttonRow:AddWidget(presetButton, 1 / 2)
    manager:Register(presetButton, "all")

    card2:AddRow(buttonRow, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 3-5: what to log
    ----------------------------------------------------------------
    AddContentCard("Dungeons", DUNGEONS, 5)
    AddContentCard("Raids", RAIDS, 5)
    AddContentCard("PvP", PVP, 3)

    ----------------------------------------------------------------
    -- Card 6: Scenarios
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Scenarios", yOffset)
    manager:Register(card6, "all")

    local scenarioRow = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local scenarioCheckbox = GUIFrame:CreateCheckbox(scenarioRow,
        "Scenarios  |cff888888- Delves, Torghast and anything else the game counts as a scenario.|r", {
        value = db.Scenario == true,
        callback = function(val) db.Scenario = val; ApplySettings() end,
    })
    scenarioRow:AddWidget(scenarioCheckbox, 1)
    manager:Register(scenarioCheckbox, "all")
    card6:AddRow(scenarioRow, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
