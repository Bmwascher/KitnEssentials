-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SoundSettingsCard.lua                               ║
-- ║  Purpose: On-Show / On-Hide sound dropdowns with test    ║
-- ║  buttons. Pulls sounds from LibSharedMedia.              ║
-- ║                                                          ║
-- ║  Pooled via KE.FramePool. Used in DungeonTimers Actions  ║
-- ║  tab (one card per render). Single shape; Configure      ║
-- ║  swaps closure slots (_db, _keys, _onChange) and rebuilds ║
-- ║  the sound list from LSM each render so newly-loaded     ║
-- ║  sound media addons surface without /reload.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs
local ipairs = ipairs

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

local function BuildSoundList()
    local list = { ["None"] = "None" }
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do
            list[name] = name
        end
    end
    return list
end

local function PlayLSMSound(soundName)
    if not soundName or soundName == "None" or not LSM then return end
    local file = LSM:Fetch("sound", soundName)
    if file then PlaySoundFile(file, "Master") end
end

---------------------------------------------------------------------------------
-- Kit factory: card + 2 dropdowns + 2 test buttons, kit-bound callbacks
---------------------------------------------------------------------------------

local function CreateSoundSettingsCardKit(holder)
    local kit = {}

    local card = GUIFrame:CreateCard(holder, "Sound", 0)
    kit.card = card
    kit.row = card -- KE.FramePool reads kit.row as the root frame

    -- Row 1: On Show sound + test button
    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local onShowDropdown = GUIFrame:CreateDropdown(row1, "On Show", {
        options = { ["None"] = "None" },
        value = "None",
        searchable = true,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.onShowSound] = key
            if kit._onChange then kit._onChange() end
        end,
    })
    row1:AddWidget(onShowDropdown, 0.7)

    local testShowBtn = GUIFrame:CreateButton(row1, "Test", {
        width = 60,
        height = 24,
        callback = function()
            if not kit._db or not kit._keys then return end
            PlayLSMSound(kit._db[kit._keys.onShowSound])
        end,
    })
    row1:AddWidget(testShowBtn, 0.3, nil, 0, -14)
    card:AddRow(row1, Theme.rowHeight)

    -- Row 2: On Hide sound + test button
    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local onHideDropdown = GUIFrame:CreateDropdown(row2, "On Hide", {
        options = { ["None"] = "None" },
        value = "None",
        searchable = true,
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.onHideSound] = key
            if kit._onChange then kit._onChange() end
        end,
    })
    row2:AddWidget(onHideDropdown, 0.7)

    local testHideBtn = GUIFrame:CreateButton(row2, "Test", {
        width = 60,
        height = 24,
        callback = function()
            if not kit._db or not kit._keys then return end
            PlayLSMSound(kit._db[kit._keys.onHideSound])
        end,
    })
    row2:AddWidget(testHideBtn, 0.3, nil, 0, -14)
    card:AddRow(row2, Theme.rowHeightLast, 0)

    kit.onShowDropdown = onShowDropdown
    kit.testShowBtn = testShowBtn
    kit.onHideDropdown = onHideDropdown
    kit.testHideBtn = testHideBtn

    -- Compatibility shim — original CreateSoundSettingsCard exposed
    -- card.soundWidgets and SetEnabled walked it.
    local soundWidgets = { onShowDropdown, testShowBtn, onHideDropdown, testHideBtn }
    card.soundWidgets = soundWidgets

    -- Override card:SetEnabled to also walk sound widgets, on top of the
    -- default alpha + click-blocker overlay from GUI-Core.
    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        for _, widget in ipairs(soundWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end

    return kit
end

local soundSettingsCardPool = KE.FramePool:New(CreateSoundSettingsCardKit)

GUIFrame:RegisterContentRebuildCallback("__SoundSettingsCardPool", function()
    soundSettingsCardPool:ReleaseAll()
end)

---------------------------------------------------------------------------------
-- Configure: re-anchor card, swap slots, refresh LSM-derived options, set values
---------------------------------------------------------------------------------

local function ConfigureSoundSettingsCardKit(kit, scrollChild, yOffset, config)
    local T = Theme
    local card = kit.card

    local title = config.title or "Sound"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback

    local keys = {
        onShowSound = dbKeys.onShowSound or "actionOnShowSound",
        onHideSound = dbKeys.onHideSound or "actionOnHideSound",
    }

    -- Swap kit slots BEFORE widget SetValue.
    kit._db = db
    kit._keys = keys
    kit._onChange = onChange

    -- Re-anchor card (Acquire reparented kit.row to scrollChild but the
    -- TOPLEFT/RIGHT anchors still point at the pool's hidden holder).
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -T.paddingSmall, 0)
    card._yOffset = yOffset or 0
    if card.titleText then card.titleText:SetText(title) end

    -- Rebuild the LSM sound list per Configure so a sound media addon that
    -- loaded after the first render gets picked up. SetOptions is cheap
    -- when the dropdown's item buttons aren't already created (collapsed
    -- state — which is what we have just-rendered).
    local soundList = BuildSoundList()
    kit.onShowDropdown:SetOptions(soundList)
    kit.onHideDropdown:SetOptions(soundList)

    -- Set values silently (Dropdown.SetValue's silent flag suppresses callback).
    kit.onShowDropdown:SetValue(db and db[keys.onShowSound] or "None", true)
    kit.onHideDropdown:SetValue(db and db[keys.onHideSound] or "None", true)

    return card
end

---------------------------------------------------------------------------------
-- Public entry: CreateSoundSettingsCard
---------------------------------------------------------------------------------

function GUIFrame:CreateSoundSettingsCard(scrollChild, yOffset, config)
    config = config or {}
    local kit = soundSettingsCardPool:Acquire(scrollChild)
    ConfigureSoundSettingsCardKit(kit, scrollChild, yOffset, config)
    return kit.card, kit.card:GetNextOffset()
end
