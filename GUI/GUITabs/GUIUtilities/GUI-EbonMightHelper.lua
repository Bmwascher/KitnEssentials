-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EbonMightHelper.lua                                 ║
-- ║  GUI: Ebon Might Helper                                  ║
-- ║  Purpose: Configuration panel for the EbonMightHelper    ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local PlaySoundFile = PlaySoundFile

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("EbonMightHelper", true)
    end
    return nil
end

GUIFrame:RegisterContent("EbonMightHelper", function(scrollChild, yOffset)
    -- Render the EbonMightTracker page first; the shared "Ebon Might" tab stacks both.
    local trackerBuilder = GUIFrame.registeredContent and GUIFrame.registeredContent["EbonMightTracker"]
    if trackerBuilder then
        yOffset = trackerBuilder(scrollChild, yOffset)
    end

    local db = KE.db and KE.db.profile.EbonMightHelper
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local EM = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyModuleState(enabled)
        if not EM then return end
        EM.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("EbonMightHelper")
        else
            KitnEssentials:DisableModule("EbonMightHelper")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Ebon Might Extension Helper", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Ebon Might Helper", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Ebon Might Helper",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 65)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Augmentation Evoker only.\n" ..
        KE:ColorTextByTheme("-") .. " Plays a warning sound when casting an extender spell that won't refresh Ebon Might\n" ..
        "   (Eruption, Fire Breath, Upheaval).",
        65, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 65, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Sound Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Sound Settings", yOffset)
    manager:Register(card2, "all")

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

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local channelDropdown = GUIFrame:CreateDropdown(row2a, "Sound Channel", {
        options = channelList,
        value = db.SoundChannel or "Master",
        callback = function(key) db.SoundChannel = key end,
    })
    row2a:AddWidget(channelDropdown, 1)
    manager:Register(channelDropdown, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row2b, "Sound", {
        options = soundList,
        value = db.SoundFile or "None",
        callback = function(key)
            db.SoundFile = key
            if key ~= "None" and LSM then
                local path = LSM:Fetch("sound", key)
                if path then PlaySoundFile(path, db.SoundChannel or "Master") end
            end
        end,
    })
    row2b:AddWidget(soundDropdown, 1)
    manager:Register(soundDropdown, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    RefreshStates()
    return yOffset
end)
