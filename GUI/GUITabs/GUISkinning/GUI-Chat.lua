-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Chat.lua                                            ║
-- ║  GUI: Chat                                                ║
-- ║  Purpose: Configuration panel for the Chat module.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs
local ipairs = ipairs
local table_insert = table.insert
local table_sort = table.sort

local function GetChatModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Chat", true)
    end
    return nil
end

local EDITBOX_POSITIONS = {
    { value = "BELOW_CHAT",        text = "Below Chat" },
    { value = "BELOW_CHAT_INSIDE", text = "Below Chat (Inside)" },
    { value = "ABOVE_CHAT",        text = "Above Chat" },
    { value = "ABOVE_CHAT_INSIDE", text = "Above Chat (Inside)" },
}

local TIMESTAMP_FORMATS = {
    { value = "NONE",           text = "None" },
    { value = "[%H:%M] ",       text = "[HH:MM]" },
    { value = "[%H:%M:%S] ",    text = "[HH:MM:SS]" },
    { value = "[%I:%M %p] ",    text = "[HH:MM AM/PM]" },
    { value = "[%I:%M:%S %p] ", text = "[HH:MM:SS AM/PM]" },
    { value = "%H:%M ",         text = "HH:MM" },
    { value = "%H:%M:%S ",      text = "HH:MM:SS" },
    { value = "%I:%M %p ",      text = "HH:MM AM/PM" },
    { value = "%I:%M:%S %p ",   text = "HH:MM:SS AM/PM" },
}

local TAB_SELECTOR_STYLES = {
    { value = "NONE",   text = "None" },
    { value = "ARROW",  text = ">Text<" },
    { value = "ARROW1", text = "> Text <" },
    { value = "ARROW2", text = "<Text>" },
    { value = "ARROW3", text = "< Text >" },
    { value = "BOX",    text = "[Text]" },
    { value = "BOX1",   text = "[ Text ]" },
    { value = "CURLY",  text = "{Text}" },
    { value = "CURLY1", text = "{ Text }" },
    { value = "CURVE",  text = "(Text)" },
    { value = "CURVE1", text = "( Text )" },
}

-- Tab font outline options: default set (None/Outline/Thick/Slug/Outline Slug)
-- only -- no SOFTOUTLINE. Chat text is styled via plain SetFont, not the
-- FontString-based soft-outline system.
local TAB_FONT_OUTLINE_OPTIONS = KE:GetFontOutlineOptions()

-- Sorted LSM sound list for the whisper dropdowns.
local function BuildWhisperSoundOptions()
    local opts = { { value = "None", text = "None" } }
    if LSM then
        local names = {}
        for name in pairs(LSM:HashTable("sound")) do
            if name ~= "None" then table_insert(names, name) end
        end
        table_sort(names)
        for _, name in ipairs(names) do
            table_insert(opts, { value = name, text = name })
        end
    end
    return opts
end

GUIFrame:RegisterContent("Chat", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Chat
    if not db then return yOffset end

    local CHAT = GetChatModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if CHAT and CHAT.ApplySettings then CHAT:ApplySettings() end
    end

    local function OnWhisperSoundsChanged(previewName)
        if CHAT and CHAT.RegisterWhisperSounds then CHAT:RegisterWhisperSounds() end
        if previewName and previewName ~= "None" and CHAT and CHAT.PlayWhisperSound then
            CHAT:PlayWhisperSound(previewName)
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Chat", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("Chat")
        else
            KitnEssentials:DisableModule("Chat")
        end
        KE:CreateReloadPrompt("Toggling the custom chat panel requires a UI reload to fully apply.")
        KE:Print("Chat Skinning: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteHeight = 65
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("- ") ..
        "Restyles chat frames and tabs into a movable custom panel with chat copy, short channel names, timestamps, message fading, and whisper sounds.\n" ..
        KE:ColorTextByTheme("- ") .. "Whisper mode is forced to In-line to prevent taint from auto-opened whisper tabs.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Chat Colors
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Chat Colors", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local classColorCheck = GUIFrame:CreateCheckbox(row2, "Class Color BNet Whispers", {
        value = db.ClassColorWhispers ~= false,
        tooltip = "Class-colors sender names on Battle.net whispers in the default Blizzard chat, matching how regular whispers are already colored.",
        callback = function(checked)
            db.ClassColorWhispers = checked
            ApplySettings()
        end,
    })
    row2:AddWidget(classColorCheck, 1)
    manager:Register(classColorCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Social
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Social", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local guildStatusCheck = GUIFrame:CreateCheckbox(row3, "Guild Login/Logout Messages", {
        value = db.GuildMemberStatus ~= false,
        tooltip = "Rewrites guild member login and logout system messages with class-colored names: green for online, red for offline.",
        callback = function(checked)
            db.GuildMemberStatus = checked
            ApplySettings()
        end,
    })
    row3:AddWidget(guildStatusCheck, 0.5)
    manager:Register(guildStatusCheck, "all")

    local inviteLinkCheck = GUIFrame:CreateCheckbox(row3, "Invite Link on Guild Logins", {
        value = db.GuildMemberStatusInviteLink ~= false,
        tooltip = "Appends a clickable Invite link to guild login messages.",
        callback = function(checked)
            db.GuildMemberStatusInviteLink = checked
            ApplySettings()
        end,
    })
    row3:AddWidget(inviteLinkCheck, 0.5)
    manager:Register(inviteLinkCheck, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Display Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row4a, "Panel Width", {
        min = 300, max = 900, step = 1,
        value = db.Width or 448,
        callback = function(value)
            db.Width = value
            ApplySettings()
        end,
    })
    row4a:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local heightSlider = GUIFrame:CreateSlider(row4a, "Panel Height", {
        min = 120, max = 500, step = 1,
        value = db.Height or 245,
        callback = function(value)
            db.Height = value
            ApplySettings()
        end,
    })
    row4a:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local editBoxPosDropdown = GUIFrame:CreateDropdown(row4b, "Edit Box Position", {
        options = EDITBOX_POSITIONS,
        value = db.EditBoxPosition or "ABOVE_CHAT_INSIDE",
        callback = function(value)
            db.EditBoxPosition = value
            ApplySettings()
        end,
    })
    row4b:AddWidget(editBoxPosDropdown, 0.5)
    manager:Register(editBoxPosDropdown, "all")

    local scrollMsgSlider = GUIFrame:CreateSlider(row4b, "Messages Per Scroll", {
        min = 1, max = 10, step = 1,
        value = db.NumScrollMessages or 3,
        callback = function(value)
            db.NumScrollMessages = value
            ApplySettings()
        end,
    })
    row4b:AddWidget(scrollMsgSlider, 0.5)
    manager:Register(scrollMsgSlider, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local maxLinesSlider = GUIFrame:CreateSlider(row4c, "Max History Lines", {
        min = 100, max = 2000, step = 50,
        value = db.MaxLines or 500,
        callback = function(value)
            db.MaxLines = value
            ApplySettings()
        end,
    })
    row4c:AddWidget(maxLinesSlider, 0.5)
    manager:Register(maxLinesSlider, "all")

    local editBoxFontSlider = GUIFrame:CreateSlider(row4c, "Edit Box Font Size", {
        min = 8, max = 24, step = 1,
        value = db.EditBoxFontSize or 14,
        callback = function(value)
            db.EditBoxFontSize = value
            ApplySettings()
        end,
    })
    row4c:AddWidget(editBoxFontSlider, 0.5)
    manager:Register(editBoxFontSlider, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local shortChannelsCheck = GUIFrame:CreateCheckbox(row4d, "Short Channel Names", {
        value = db.ShortChannels ~= false,
        callback = function(checked)
            db.ShortChannels = checked
            ApplySettings()
        end,
    })
    row4d:AddWidget(shortChannelsCheck, 0.5)
    manager:Register(shortChannelsCheck, "all")

    local roleIconsCheck = GUIFrame:CreateCheckbox(row4d, "Role Icons in Group Chat", {
        value = db.RoleIcons ~= false,
        tooltip = "Shows tank, healer, and DPS role icons before sender names in party, raid, and instance chat.",
        callback = function(checked)
            db.RoleIcons = checked
            ApplySettings()
        end,
    })
    row4d:AddWidget(roleIconsCheck, 0.5)
    manager:Register(roleIconsCheck, "all")
    card4:AddRow(row4d, Theme.rowHeight)

    local row4e = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local fadeCheck = GUIFrame:CreateCheckbox(row4e, "Fade Chat Text", {
        value = db.FadeEnabled ~= false,
        callback = function(checked)
            db.FadeEnabled = checked
            ApplySettings()
        end,
    })
    row4e:AddWidget(fadeCheck, 0.5)
    manager:Register(fadeCheck, "all")

    local fadeTimeSlider = GUIFrame:CreateSlider(row4e, "Fade After (seconds)", {
        min = 5, max = 120, step = 5,
        value = db.FadeTime or 30,
        callback = function(value)
            db.FadeTime = value
            ApplySettings()
        end,
    })
    row4e:AddWidget(fadeTimeSlider, 0.5)
    manager:Register(fadeTimeSlider, "all")
    card4:AddRow(row4e, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 6: Font
    ----------------------------------------------------------------
    local fontCard, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        fontSizeRange = { 8, 24 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 7: Backdrop
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card7, "all")

    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local panelBackdropCheck = GUIFrame:CreateCheckbox(row7a, "Panel Backdrop", {
        value = db.Backdrop.Enabled ~= false,
        callback = function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
        end,
    })
    row7a:AddWidget(panelBackdropCheck, 0.5)
    manager:Register(panelBackdropCheck, "all")

    local tabBackdropCheck = GUIFrame:CreateCheckbox(row7a, "Tab Bar Backdrop", {
        value = db.TabBackdrop.Enabled ~= false,
        callback = function(checked)
            db.TabBackdrop.Enabled = checked
            ApplySettings()
        end,
    })
    row7a:AddWidget(tabBackdropCheck, 0.5)
    manager:Register(tabBackdropCheck, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local panelColorPicker = GUIFrame:CreateColorPicker(row7b, "Panel Color", {
        color = db.Backdrop.Color or { 0.031, 0.031, 0.031, 0.8 },
        callback = function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7b:AddWidget(panelColorPicker, 0.5)
    manager:Register(panelColorPicker, "all")

    local panelBorderColorPicker = GUIFrame:CreateColorPicker(row7b, "Panel Border Color", {
        color = db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7b:AddWidget(panelBorderColorPicker, 0.5)
    manager:Register(panelBorderColorPicker, "all")
    card7:AddRow(row7b, Theme.rowHeight)

    -- Edit Box Border Color has no control here: the edit box border is
    -- chat-type colored on every header update (say/whisper/channel), same
    -- so a static color option would be applied then instantly overridden.
    local row7c = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local editBoxColorPicker = GUIFrame:CreateColorPicker(row7c, "Edit Box Color", {
        color = db.EditBox.BackdropColor or { 0.031, 0.031, 0.031, 1 },
        callback = function(r, g, b, a)
            db.EditBox.BackdropColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7c:AddWidget(editBoxColorPicker, 0.5)
    manager:Register(editBoxColorPicker, "all")

    local tabColorPicker = GUIFrame:CreateColorPicker(row7c, "Tab Bar Color", {
        color = db.TabBackdrop.Color or { 0, 0, 0, 0.2 },
        callback = function(r, g, b, a)
            db.TabBackdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7c:AddWidget(tabColorPicker, 0.5)
    manager:Register(tabColorPicker, "all")
    card7:AddRow(row7c, Theme.rowHeight)

    local row7d = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local tabBorderColorPicker = GUIFrame:CreateColorPicker(row7d, "Tab Bar Border Color", {
        color = db.TabBackdrop.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.TabBackdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7d:AddWidget(tabBorderColorPicker, 0.5)
    manager:Register(tabBorderColorPicker, "all")
    card7:AddRow(row7d, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Timestamps
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Timestamps", yOffset)
    manager:Register(card8, "all")

    local row8a = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local timestampFormatDropdown = GUIFrame:CreateDropdown(row8a, "Timestamp Format", {
        options = TIMESTAMP_FORMATS,
        value = db.TimestampFormat or "NONE",
        callback = function(value)
            db.TimestampFormat = value
            ApplySettings()
        end,
    })
    row8a:AddWidget(timestampFormatDropdown, 0.5)
    manager:Register(timestampFormatDropdown, "all")

    local useLocalTimeCheck = GUIFrame:CreateCheckbox(row8a, "Use Local Time", {
        value = db.UseLocalTime ~= false,
        callback = function(checked)
            db.UseLocalTime = checked
            ApplySettings()
        end,
    })
    row8a:AddWidget(useLocalTimeCheck, 0.5)
    manager:Register(useLocalTimeCheck, "all")
    card8:AddRow(row8a, Theme.rowHeight)

    local row8b = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    local timestampColorEnabledCheck = GUIFrame:CreateCheckbox(row8b, "Custom Timestamp Color", {
        value = db.TimestampColorEnabled ~= false,
        callback = function(checked)
            db.TimestampColorEnabled = checked
            ApplySettings()
        end,
    })
    row8b:AddWidget(timestampColorEnabledCheck, 0.5)
    manager:Register(timestampColorEnabledCheck, "all")

    local timestampColorPicker = GUIFrame:CreateColorPicker(row8b, "Timestamp Color", {
        color = { db.TimestampColor.r or 0.6, db.TimestampColor.g or 0.6, db.TimestampColor.b or 0.6, 1 },
        callback = function(r, g, b)
            db.TimestampColor.r, db.TimestampColor.g, db.TimestampColor.b = r, g, b
            ApplySettings()
        end,
    })
    row8b:AddWidget(timestampColorPicker, 0.5)
    manager:Register(timestampColorPicker, "all")
    card8:AddRow(row8b, Theme.rowHeightLast, 0)

    yOffset = card8:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Chat Tabs
    ----------------------------------------------------------------
    local card9 = GUIFrame:CreateCard(scrollChild, "Chat Tabs", yOffset)
    manager:Register(card9, "all")

    local row9a = GUIFrame:CreateRow(card9.content, Theme.rowHeight)
    local tabFontSizeSlider = GUIFrame:CreateSlider(row9a, "Tab Font Size", {
        min = 8, max = 20, step = 1,
        value = db.TabFontSize or 12,
        callback = function(value)
            db.TabFontSize = value
            ApplySettings()
        end,
    })
    row9a:AddWidget(tabFontSizeSlider, 0.5)
    manager:Register(tabFontSizeSlider, "all")

    local tabFontOutlineDropdown = GUIFrame:CreateDropdown(row9a, "Tab Font Outline", {
        options = TAB_FONT_OUTLINE_OPTIONS,
        value = KE:NormalizeFontOutline(db.TabFontOutline or "OUTLINE"),
        callback = function(value)
            db.TabFontOutline = value
            ApplySettings()
        end,
    })
    row9a:AddWidget(tabFontOutlineDropdown, 0.5)
    manager:Register(tabFontOutlineDropdown, "all")
    card9:AddRow(row9a, Theme.rowHeight)

    local row9b = GUIFrame:CreateRow(card9.content, Theme.rowHeight)
    local fadeTabsCheck = GUIFrame:CreateCheckbox(row9b, "Fade Tab Text", {
        value = db.FadeTabs ~= false,
        callback = function(checked)
            db.FadeTabs = checked
            ApplySettings()
        end,
    })
    row9b:AddWidget(fadeTabsCheck, 0.5)
    manager:Register(fadeTabsCheck, "all")

    local tabTextColorPicker = GUIFrame:CreateColorPicker(row9b, "Tab Text Color", {
        color = { db.TabTextColor.r or 0.57, db.TabTextColor.g or 0.57, db.TabTextColor.b or 0.57, 1 },
        callback = function(r, g, b)
            db.TabTextColor.r, db.TabTextColor.g, db.TabTextColor.b = r, g, b
            ApplySettings()
        end,
    })
    row9b:AddWidget(tabTextColorPicker, 0.5)
    manager:Register(tabTextColorPicker, "all")
    card9:AddRow(row9b, Theme.rowHeight)

    local row9c = GUIFrame:CreateRow(card9.content, Theme.rowHeight)
    local tabSelectedEnabledCheck = GUIFrame:CreateCheckbox(row9c, "Custom Selected Tab Color", {
        value = db.TabSelectedTextEnabled ~= false,
        callback = function(checked)
            db.TabSelectedTextEnabled = checked
            ApplySettings()
        end,
    })
    row9c:AddWidget(tabSelectedEnabledCheck, 0.5)
    manager:Register(tabSelectedEnabledCheck, "all")

    local tabSelectedColorPicker = GUIFrame:CreateColorPicker(row9c, "Selected Tab Color", {
        color = { db.TabSelectedTextColor.r or 1, db.TabSelectedTextColor.g or 0, db.TabSelectedTextColor.b or 0.549, 1 },
        callback = function(r, g, b)
            db.TabSelectedTextColor.r, db.TabSelectedTextColor.g, db.TabSelectedTextColor.b = r, g, b
            ApplySettings()
        end,
    })
    row9c:AddWidget(tabSelectedColorPicker, 0.5)
    manager:Register(tabSelectedColorPicker, "all")
    card9:AddRow(row9c, Theme.rowHeight)

    local row9d = GUIFrame:CreateRow(card9.content, Theme.rowHeightLast)
    local tabSelectorDropdown = GUIFrame:CreateDropdown(row9d, "Selected Tab Marker", {
        options = TAB_SELECTOR_STYLES,
        value = db.TabSelector or "NONE",
        callback = function(value)
            db.TabSelector = value
            ApplySettings()
        end,
    })
    row9d:AddWidget(tabSelectorDropdown, 0.5)
    manager:Register(tabSelectorDropdown, "all")

    local tabSelectorColorPicker = GUIFrame:CreateColorPicker(row9d, "Marker Color", {
        color = { db.TabSelectorColor.r or 1, db.TabSelectorColor.g or 1, db.TabSelectorColor.b or 1, 1 },
        callback = function(r, g, b)
            db.TabSelectorColor.r, db.TabSelectorColor.g, db.TabSelectorColor.b = r, g, b
            ApplySettings()
        end,
    })
    row9d:AddWidget(tabSelectorColorPicker, 0.5)
    manager:Register(tabSelectorColorPicker, "all")
    card9:AddRow(row9d, Theme.rowHeightLast, 0)

    yOffset = card9:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 10: Whisper Sounds
    ----------------------------------------------------------------
    local card10 = GUIFrame:CreateCard(scrollChild, "Whisper Sounds", yOffset)
    manager:Register(card10, "all")

    local soundOptions = BuildWhisperSoundOptions()

    local row10a = GUIFrame:CreateRow(card10.content, Theme.rowHeight)
    local whisperSoundEnabledCheck = GUIFrame:CreateCheckbox(row10a, "Play Sound On Whisper", {
        value = db.WhisperSounds.Enabled == true,
        callback = function(checked)
            db.WhisperSounds.Enabled = checked
            OnWhisperSoundsChanged()
        end,
    })
    row10a:AddWidget(whisperSoundEnabledCheck, 1)
    manager:Register(whisperSoundEnabledCheck, "all")
    card10:AddRow(row10a, Theme.rowHeight)

    local row10b = GUIFrame:CreateRow(card10.content, Theme.rowHeightLast)
    local whisperSoundDropdown = GUIFrame:CreateDropdown(row10b, "Whisper Sound", {
        options = soundOptions,
        value = db.WhisperSounds.WhisperSound or "None",
        callback = function(value)
            db.WhisperSounds.WhisperSound = value
            OnWhisperSoundsChanged(value)
        end,
    })
    row10b:AddWidget(whisperSoundDropdown, 0.5)
    manager:Register(whisperSoundDropdown, "all")

    local bnetWhisperSoundDropdown = GUIFrame:CreateDropdown(row10b, "Battle.net Whisper Sound", {
        options = soundOptions,
        value = db.WhisperSounds.BNetWhisperSound or "None",
        callback = function(value)
            db.WhisperSounds.BNetWhisperSound = value
            OnWhisperSoundsChanged(value)
        end,
    })
    row10b:AddWidget(bnetWhisperSoundDropdown, 0.5)
    manager:Register(bnetWhisperSoundDropdown, "all")
    card10:AddRow(row10b, Theme.rowHeightLast, 0)

    yOffset = card10:GetNextOffset()

    manager:UpdateAll(db.Enabled == true)
    return yOffset
end)
