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
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if GVA then GVA:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not GVA then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("GreatVaultAlert")
        else KitnEssentials:DisableModule("GreatVaultAlert") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local channelList = {
        { key = "Master", text = "Master" },
        { key = "SFX", text = "SFX" },
        { key = "Music", text = "Music" },
        { key = "Ambience", text = "Ambience" },
    }

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Great Vault Spec Alert", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Great Vault Alert", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Great Vault Spec Alert",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 40)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows your loot specialization when opening the Great Vault.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 40, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Alert Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    manager:Register(card2, "all")

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do soundList[name] = name end
    end

    -- Alert modes (chat + sound on/off)
    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local chatCheck = GUIFrame:CreateCheckbox(row2a, "Show Chat Message", {
        value = db.ShowChatMessage ~= false,
        callback = function(checked) db.ShowChatMessage = checked end,
    })
    row2a:AddWidget(chatCheck, 0.5)
    manager:Register(chatCheck, "all")

    local soundCheck = GUIFrame:CreateCheckbox(row2a, "Play Sound", {
        value = db.PlaySound ~= false,
        callback = function(checked) db.PlaySound = checked end,
    })
    row2a:AddWidget(soundCheck, 0.5)
    manager:Register(soundCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2sep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(row2sep)
    row2sep:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    card2:AddRow(row2sep, Theme.rowHeightSeparator)

    -- Sound config (both relevant only if Play Sound is on)
    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
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
    row2b:AddWidget(soundDropdown, 0.5)
    manager:Register(soundDropdown, "all")

    local channelDropdown = GUIFrame:CreateDropdown(row2b, "Sound Channel", {
        options = channelList,
        value = db.SoundChannel or "Master",
        callback = function(key) db.SoundChannel = key end,
    })
    row2b:AddWidget(channelDropdown, 0.5)
    manager:Register(channelDropdown, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    -- Visual timing
    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local durationSlider = GUIFrame:CreateSlider(row2c, "Alert Duration", {
        min = 1, max = 10, step = 0.5,
        value = db.AlertDuration or 3,
        callback = function(val) db.AlertDuration = val end,
    })
    row2c:AddWidget(durationSlider, 1)
    manager:Register(durationSlider, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 32 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)
