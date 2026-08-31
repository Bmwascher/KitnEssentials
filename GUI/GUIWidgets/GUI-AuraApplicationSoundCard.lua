---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local PlaySoundFile = PlaySoundFile

----------------------------------------------------------------
-- Card 5: Sound
--
-- Plays the configured sound when any enabled allowlist row lands on
-- you. Blizzard's sound-trigger API takes a spell ID rather than a
-- filter, so the registry is one registration per enabled row. Big
-- defensives are not on the allowlist and stay silent.
----------------------------------------------------------------
function GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, config)
    config = config or {}
    assert(type(config.db) == "table", "CreateAuraApplicationSoundCard requires db")

    local db = config.db
    local dbKeys = config.dbKeys or {}
    local enabledKey = dbKeys.enabled or "SoundEnabled"
    local nameKey = dbKeys.name or "SoundName"

    local card = GUIFrame:CreateCard(scrollChild, config.title or "Sound", yOffset)
    local innerManager = GUIFrame:CreateWidgetStateManager()

    local notes = config.notes or {}
    for i = 1, #notes do
        card:AddNote(notes[i])
    end

    local row5a = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local soundEnabledCheck = GUIFrame:CreateCheckbox(row5a, "Enable Sound", {
        value = db[enabledKey] ~= false,
        callback = function(checked)
            db[enabledKey] = checked
            if config.onChangeCallback then config.onChangeCallback() end
        end,
    })
    row5a:AddWidget(soundEnabledCheck, 1)
    innerManager:Register(soundEnabledCheck, "all")
    card:AddRow(row5a, Theme.rowHeight)

    -- Separator between Enable toggle and the sound dropdown/test row
    local row5sep = GUIFrame:CreateRow(card.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sep5, 1)
    innerManager:Register(sep5, "all")
    card:AddRow(row5sep, Theme.rowHeightSeparator)

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do
            soundList[name] = name
        end
    end
    soundList["None"] = "None"

    local row5b = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row5b, "On Application Sound", {
        options = soundList,
        value = db[nameKey] or "None",
        searchable = true,
        callback = function(key)
            db[nameKey] = key
            if config.onChangeCallback then config.onChangeCallback() end
        end,
    })
    row5b:AddWidget(soundDropdown, 0.5)
    innerManager:Register(soundDropdown, "all")

    -- Test button: plays whatever sound is currently selected. y=-12 places
    -- the 28px button center on the dropdown bar center (matches the pattern
    -- used in DungeonTimers detail panel).
    local soundTestBtn = GUIFrame:CreateButton(row5b, "Test", {
        height = 28,
        callback = function()
            local name = db[nameKey]
            if not name or name == "None" or not LSM then return end
            local soundPath = LSM:Fetch("sound", name)
            if soundPath then PlaySoundFile(soundPath) end
        end,
    })
    row5b:AddWidget(soundTestBtn, 0.5, nil, 0, -12)
    innerManager:Register(soundTestBtn, "all")
    card:AddRow(row5b, Theme.rowHeightLast, 0)

    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        innerManager:UpdateAll(enabled)
    end

    return card, card:GetNextOffset()
end
