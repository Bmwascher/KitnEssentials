-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersCfg.lua                                ║
-- ║  DTimers_General page — module enable, role filter,      ║
-- ║  sound master controls, curated-coverage stats, and      ║
-- ║  override maintenance (module-wide + per-dungeon Reset). ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local pairs = pairs
local ipairs = ipairs
local string_format = string.format

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.DungeonTimers
end

-- Module-level preview teardown. Fires whenever the user switches to ANY
-- other sidebar item (contentCleanupCallbacks) or closes the GUI window
-- (onCloseCallbacks). Per-page onCloseCallbacks in Bars/Texts only cover the
-- close path; without this hook, leaving DTimers_Bars for an unrelated module
-- leaves the preview bars stranded on screen.
local function HideAllPreviews()
    if not KitnEssentials then return end
    local mod = KitnEssentials:GetModule("DungeonTimers", true)
    if not mod then return end
    if mod.HideSettingsBarPreviews then mod:HideSettingsBarPreviews() end
    if mod.HideSettingsTextPreviews then mod:HideSettingsTextPreviews() end
end

GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
GUIFrame.contentCleanupCallbacks["DungeonTimers"] = HideAllPreviews

GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DungeonTimers"] = HideAllPreviews

-- Dungeon registry. Duplicated from GUI-DungeonTimersDungeon.lua's local
-- DUNGEONS (Cfg loads first per GUI.xml so a shared reference there would
-- be nil at file-parse time). Keep in sync when adding a new dungeon.
-- iconID = Blizzard texture FileID for the dungeon's encounter-journal icon.
local DUNGEONS = {
    { key = "AlgetharAcademy",    name = "Algeth'ar Academy",       iconID = 4578414 },
    { key = "MagistersTerrace",   name = "Magisters' Terrace",      iconID = 7439625 },
    { key = "MaisaraCaverns",     name = "Maisara Caverns",         iconID = 7322719 },
    { key = "NexusPointXenas",    name = "Nexus-Point Xenas",       iconID = 7553062 },
    { key = "PitOfSaron",         name = "Pit of Saron",            iconID = 343641 },
    { key = "SeatOfTriumvirate",  name = "Seat of the Triumvirate", iconID = 1711340 },
    { key = "Skyreach",           name = "Skyreach",                iconID = 1002596 },
    { key = "WindrunnerSpire",    name = "Windrunner Spire",        iconID = 7266215 },
}

-- Sound channel dropdown options. Matches Blizzard's PlaySoundFile second
-- argument — channels are gated by their respective volume sliders, so
-- "SFX" lets the user mute timer sounds independently of dialog/music.
-- Array-of-tables form preserves dropdown order (hash form is pairs()-iterated
-- and unordered).
local SOUND_CHANNELS = {
    { key = "Master",   text = "Master" },
    { key = "SFX",      text = "SFX" },
    { key = "Dialog",   text = "Dialog" },
    { key = "Music",    text = "Music" },
    { key = "Ambience", text = "Ambience" },
}

local function CountCoverage()
    local dungeonSet, encounters, spells = {}, 0, 0
    for _, enc in pairs(KE.EncounterData or {}) do
        encounters = encounters + 1
        if enc.dungeon then dungeonSet[enc.dungeon] = true end
        if enc.spells then
            for _ in pairs(enc.spells) do spells = spells + 1 end
        end
    end
    local dungeons = 0
    for _ in pairs(dungeonSet) do dungeons = dungeons + 1 end
    return dungeons, encounters, spells
end

-- Clears every per-spell + per-phase override entry whose owner encounter
-- lives in the given dungeon. Leaves global display settings (BarDisplay /
-- TextDisplay / BarGroup / TextGroup) alone — those are shared across all
-- dungeons, so a per-dungeon reset that touched them would be misleading.
-- Pass dungeonKey = nil to reset everything.
local function ResetOverridesForDungeon(DT, dungeonKey)
    if not DT then return end
    for encID, enc in pairs(KE.EncounterData or {}) do
        if not dungeonKey or enc.dungeon == dungeonKey then
            if enc.spells and DT.ResetSpellOverrides then
                for spellId in pairs(enc.spells) do
                    DT:ResetSpellOverrides(spellId)
                end
            end
            if enc.phases and DT.ResetPhaseOverrides and DT.MakePhaseRuleKey then
                for i in ipairs(enc.phases) do
                    local key = DT:MakePhaseRuleKey(encID, i)
                    if key then DT:ResetPhaseOverrides(key) end
                end
            end
        end
    end
end

GUIFrame:RegisterContent("DTimers_General", function(scrollChild, yOffset)
    local Theme = KE.Theme
    local db = GetSettingsDB()
    if not db then return yOffset end

    local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)

    local function ApplyModuleState(enabled)
        db.Enabled = enabled
        if not DT then return end
        if enabled then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            KitnEssentials:DisableModule("DungeonTimers")
        end
    end

    ---------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Timers", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dungeon Timers", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
            KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
        end,
        msgPopup = true,
        msgText = "Dungeon Timers",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 2: Role Filter
    ---------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Role Filter", yOffset)
    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local roleCheck = GUIFrame:CreateCheckbox(row2, "Filter bars by your role/spec", {
        value = db.RoleFilterEnabled == true,
        callback = function(checked)
            db.RoleFilterEnabled = checked
        end,
    })
    row2:AddWidget(roleCheck, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 3: Sounds — mute toggle + channel dropdown side by side
    ---------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Sounds", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local muteCheck = GUIFrame:CreateCheckbox(row3, "Mute all preset sounds", {
        value = db.MutePresetSounds == true,
        callback = function(checked)
            db.MutePresetSounds = checked
        end,
    })
    row3:AddWidget(muteCheck, 0.5)
    local channelDropdown = GUIFrame:CreateDropdown(row3, "Sound channel", {
        options = SOUND_CHANNELS,
        value = db.SoundChannel or "Master",
        callback = function(key)
            db.SoundChannel = key
        end,
    })
    row3:AddWidget(channelDropdown, 0.5)
    card3:AddRow(row3, Theme.rowHeightLast, 0)
    yOffset = card3:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 4: Reset Overrides
    -- Layout per dungeon row: [icon] [name] ... [Reset btn flush-right].
    -- Module-wide "Reset All Dungeons" sits at the BOTTOM of the card after
    -- the per-dungeon list (least-frequent / most-destructive action goes
    -- last so the eye scans the per-dungeon rows first). All Reset buttons
    -- use red text (REMOVE_COLOR) matching the Nicknames Remove-button
    -- convention for destructive actions.
    ---------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Reset Overrides", yOffset)
    card4:AddLabel("Clears your per-spell and per-phase overrides (role, enable, color, sound, display, etc.).")
    card4:AddLabel("Global bar/text style and position are NOT touched.")

    -- Separator between the description header and the dungeon list.
    local rowDescSep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local descSep = GUIFrame:CreateSeparator(rowDescSep)
    rowDescSep:AddWidget(descSep, 1)
    card4:AddRow(rowDescSep, Theme.rowHeightSeparator)

    -- Per-dungeon row metrics. Manual positioning for icon/label/button so
    -- the button's right edge aligns precisely with the separator + Reset
    -- All button below (both end at row-right - paddingSmall via AddWidget's
    -- default-spacing math). AddWidget's per-widget width calculation made
    -- the button visually shorter than Reset All in practice, so this path
    -- skips it for the button.
    local ROW_H           = 36
    local BTN_H           = 30
    local BTN_W           = 140
    local ICON_SIZE       = 28
    local RIGHT_INSET     = Theme.paddingSmall   -- match AddWidget(widget, 1)'s effective right inset
    local REMOVE_COLOR    = { 0.9, 0.2, 0.2, 1 } -- red, matches Nicknames

    for _, dungeon in ipairs(DUNGEONS) do
        local row = GUIFrame:CreateRow(card4.content, ROW_H)

        local iconHolder = CreateFrame("Frame", nil, row)
        iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
        iconHolder:SetPoint("LEFT", row, "LEFT", 0, 0)

        local icon = iconHolder:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -1, 1)
        if dungeon.iconID then
            icon:SetTexture(dungeon.iconID)
            if KE.ApplyIconZoom then KE:ApplyIconZoom(icon) end
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        local iconBorder = CreateFrame("Frame", nil, iconHolder, "BackdropTemplate")
        iconBorder:SetAllPoints()
        iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        iconBorder:SetBackdropBorderColor(0, 0, 0, 1)

        local btn = GUIFrame:CreateButton(row, "Reset", {
            width  = BTN_W,
            height = BTN_H,
            callback = function()
                KE:CreatePrompt(
                    "Reset " .. dungeon.name,
                    "Clear every per-spell and per-phase override for " ..
                    dungeon.name .. "?",
                    false, nil, false, nil, nil, nil, nil,
                    function() ResetOverridesForDungeon(DT, dungeon.key) end,
                    nil,
                    "Reset",
                    "Cancel"
                )
            end,
        })
        if btn.text then
            btn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
        end
        -- Manual anchor — RIGHT-to-RIGHT vertically centers both edges' midpoints,
        -- so no yOffset hack is needed for vertical alignment.
        btn:SetParent(row)
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", row, "RIGHT", -RIGHT_INSET, 0)
        btn:SetSize(BTN_W, BTN_H)

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT",   iconHolder, "RIGHT", Theme.paddingMedium, 0)
        label:SetPoint("RIGHT",  btn,        "LEFT",  -Theme.paddingMedium, 0)
        label:SetPoint("TOP",    row,        "TOP",    0, 0)
        label:SetPoint("BOTTOM", row,        "BOTTOM", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        KE:ApplyThemeFont(label, "large")
        label:SetText(dungeon.name)

        card4:AddRow(row, ROW_H, 2)
    end

    -- Separator before the destructive Reset-All action.
    local rowSep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep, 1)
    card4:AddRow(rowSep, Theme.rowHeightSeparator)

    -- Module-wide Reset All at the BOTTOM of the card.
    local rowAll = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local resetAllBtn = GUIFrame:CreateButton(rowAll, "Reset All Dungeons", {
        callback = function()
            KE:CreatePrompt(
                "Reset All Overrides",
                "Clear every per-spell and per-phase override across ALL dungeons?\n" ..
                "Global display settings (bar size, font, position) will be kept.",
                false, nil, false, nil, nil, nil, nil,
                function() ResetOverridesForDungeon(DT, nil) end,
                nil,
                "Reset",
                "Cancel"
            )
        end,
    })
    if resetAllBtn.text then
        resetAllBtn.text:SetTextColor(REMOVE_COLOR[1], REMOVE_COLOR[2], REMOVE_COLOR[3], REMOVE_COLOR[4])
    end
    rowAll:AddWidget(resetAllBtn, 1)
    card4:AddRow(rowAll, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 5: Curated Coverage (footer-style info card, read-only)
    ---------------------------------------------------------------------------
    local dungeons, encounters, spells = CountCoverage()
    local card5 = GUIFrame:CreateCard(scrollChild, "Curated Coverage", yOffset)
    card5:AddLabel(string_format(
        "%d dungeons / %d encounters / %d curated spells.",
        dungeons, encounters, spells))
    card5:AddLabel("All hand-tuned by Cruzer's Kittens.")
    yOffset = card5:GetNextOffset()

    return yOffset
end)
