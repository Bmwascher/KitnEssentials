-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-GreatVaultAlert.lua                                 ║
-- ║  GUI: Great Vault Alert                                  ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           GreatVaultAlert module.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM
local PlaySoundFile = PlaySoundFile
local table_insert = table.insert
local ipairs, pairs = ipairs, pairs

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("GreatVaultAlert", true)
    end
    return nil
end

GUIFrame:RegisterContent("GreatVaultAlert", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.GreatVaultAlert
    if not db then return yOffset end

    local GVA = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if GVA then GVA:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not GVA then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("GreatVaultAlert")
        else KitnEssentials:DisableModule("GreatVaultAlert") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    -- Font / outline lists
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    local channelList = {
        { key = "Master", text = "Master" },
        { key = "SFX", text = "SFX" },
        { key = "Music", text = "Music" },
        { key = "Ambience", text = "Ambience" },
    }

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Great Vault Spec Alert", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Great Vault Alert", db.Enabled ~= false,
        function(checked) db.Enabled = checked; ApplyState(checked); UpdateAllWidgetStates() end,
        true, "Great Vault Spec Alert", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)

    local chatCheck = GUIFrame:CreateCheckbox(row1, "Show Chat Message", db.ShowChatMessage ~= false,
        function(checked) db.ShowChatMessage = checked end)
    row1:AddWidget(chatCheck, 0.5)
    table_insert(allWidgets, chatCheck)
    card1:AddRow(row1, 40)

    local noteHeight = 40
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows your loot specialization when opening the Great Vault.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Alert Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Sound toggle + sound picker
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local soundCheck = GUIFrame:CreateCheckbox(row2a, "Play Sound", db.PlaySound ~= false,
        function(checked) db.PlaySound = checked end)
    row2a:AddWidget(soundCheck, 0.4)
    table_insert(allWidgets, soundCheck)

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do soundList[name] = name end
    end
    local soundDropdown = GUIFrame:CreateDropdown(row2a, "Sound", soundList, db.SoundFile or "None", 50,
        function(key)
            db.SoundFile = key
            if key ~= "None" and LSM then
                local path = LSM:Fetch("sound", key)
                if path then PlaySoundFile(path, db.SoundChannel or "Master") end
            end
        end)
    row2a:AddWidget(soundDropdown, 0.6)
    table_insert(allWidgets, soundDropdown)
    card2:AddRow(row2a, 40)

    -- Sound channel
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local channelDropdown = GUIFrame:CreateDropdown(row2b, "Sound Channel", channelList, db.SoundChannel or "Master", 45,
        function(key) db.SoundChannel = key end)
    row2b:AddWidget(channelDropdown, 0.5)
    table_insert(allWidgets, channelDropdown)

    local durationSlider = GUIFrame:CreateSlider(row2b, "Alert Duration", 1, 10, 0.5, db.AlertDuration or 3, 50,
        function(val) db.AlertDuration = val end)
    row2b:AddWidget(durationSlider, 0.5)
    table_insert(allWidgets, durationSlider)
    card2:AddRow(row2b, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
    local card3, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = { selfPoint = "AnchorFrom", anchorPoint = "AnchorTo", xOffset = "XOffset", yOffset = "YOffset" },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    table_insert(allWidgets, card3)
    yOffset = posOffset

    ---------------------------------------------------------------------------------
    -- Card 4: Font Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key) db.FontFace = key; ApplySettings() end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row4a, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key) db.FontOutline = key; ApplySettings() end)
    row4a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local sizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 32, 1, db.FontSize or 22, 50,
        function(val) db.FontSize = val; ApplySettings() end)
    row4b:AddWidget(sizeSlider, 0.5)
    table_insert(allWidgets, sizeSlider)
    card4:AddRow(row4b, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    return yOffset
end)
