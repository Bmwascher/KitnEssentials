-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local PlaySoundFile = PlaySoundFile

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

local function GetModule()
    return KitnEssentials:GetModule("EbonMightHelper", true)
end

GUIFrame:RegisterContent("EbonMightHelper", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.EbonMightHelper
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local EM = GetModule()
    local allWidgets = {}

    local function ApplyModuleState(enabled)
        if not EM then return end
        EM.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EbonMightHelper")
        else
            KitnEssentials:DisableModule("EbonMightHelper")
        end
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
    local card1 = GUIFrame:CreateCard(scrollChild, "Ebon Might Extension Helper", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Ebon Might Helper", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Ebon Might Helper", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Note
    local noteHeight = 65
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Augmentation Evoker only.\n"
            .. KE:ColorTextByTheme("-") .. " Plays a warning sound when casting an extender spell\n"
            .. "   (Eruption, Fire Breath, Upheaval) that won't refresh Ebon Might.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Sound Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Sound Settings", yOffset)
    table_insert(allWidgets, card2)

    local soundList = { None = "None" }
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do soundList[name] = name end
    end

    local channelList = {
        { key = "Master", text = "Master" },
        { key = "SFX", text = "SFX" },
        { key = "Music", text = "Music" },
        { key = "Ambience", text = "Ambience" },
        { key = "Dialog", text = "Dialog" },
    }

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local channelDropdown = GUIFrame:CreateDropdown(row2a, "Sound Channel", channelList,
        db.SoundChannel or "Master", 30,
        function(key)
            db.SoundChannel = key
        end)
    row2a:AddWidget(channelDropdown, 1)
    table_insert(allWidgets, channelDropdown)
    card2:AddRow(row2a, 40)

    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local soundDropdown = GUIFrame:CreateDropdown(row2b, "Sound", soundList,
        db.SoundFile or "None", 70,
        function(key)
            db.SoundFile = key
            -- Play preview
            if key ~= "None" and LSM then
                local path = LSM:Fetch("sound", key)
                if path then PlaySoundFile(path, db.SoundChannel or "Master") end
            end
        end)
    row2b:AddWidget(soundDropdown, 1)
    table_insert(allWidgets, soundDropdown)
    card2:AddRow(row2b, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
