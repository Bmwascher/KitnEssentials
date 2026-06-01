-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-InnervateTracker.lua                                ║
-- ║  GUI: Innervate Tracker                                  ║
-- ║  Purpose: Configuration panel for the InnervateTracker   ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local UnitClass = UnitClass

local SUPPORTED = {
    DRUID   = true,
    PALADIN = true,
    PRIEST  = true,
    SHAMAN  = true,
    MONK    = true,
    EVOKER  = true,
}

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("InnervateTracker", true)
end

GUIFrame:RegisterContent("InnervateTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.InnervateTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    -- Class-gate notice: the module silently does nothing on unsupported classes.
    -- Warn the user upfront rather than leaving them puzzled.
    local _, playerClass = UnitClass("player")
    if not SUPPORTED[playerClass] then
        local noticeCard = GUIFrame:CreateCard(scrollChild, "Innervate Tracker", yOffset)
        noticeCard:AddLabel(
            "Innervate Tracker only applies to healer-capable classes.\n\n" ..
            "Your current class (" .. (playerClass or "Unknown") .. ") cannot receive " ..
            "|cffffd100Innervate|r, so the tracker is inactive on this character. " ..
            "Settings are saved to your profile and will apply if you switch to a " ..
            "|cffffd100Druid, Paladin, Priest, Shaman, Monk, or Evoker|r."
        )
        return noticeCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        local IT = GetModule()
        if IT and IT.ApplySettings then IT:ApplySettings() end
    end

    local function UpdateAllWidgetStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Innervate Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)

    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Innervate Tracker", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            local IT = GetModule()
            if IT then
                if checked then KitnEssentials:EnableModule("InnervateTracker")
                else KitnEssentials:DisableModule("InnervateTracker") end
            end
            UpdateAllWidgetStates()
        end,
        msgPopup = true,
        msgText = "Innervate Tracker",
    })
    row1:AddWidget(enableCheck, (2 / 3))

    local previewBtn
    previewBtn = GUIFrame:CreateButton(row1, "Show Preview", {
        height = 30,
        callback = function()
            local IT = GetModule()
            if IT and IT.TogglePreview then
                local isActive = IT:TogglePreview()
                previewBtn:SetLabel(isActive and "Hide Preview" or "Show Preview")
            end
        end,
    })
    row1:AddWidget(previewBtn, (1 / 3), nil, 0, -6)
    local _IT = GetModule()
    if _IT and _IT.IsPreviewActive and _IT:IsPreviewActive() then
        previewBtn:SetLabel("Hide Preview")
    end
    card1:AddRow(row1, Theme.rowHeight)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")

    -- Icon Size
    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", {
        min = 20, max = 120, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2a:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local rowSep2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    card2:AddRow(rowSep2, Theme.rowHeightSeparator)

    -- Show Label + Label Color (paired)
    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local showLabelCheck = GUIFrame:CreateCheckbox(row2b, "Show Label", {
        value = db.ShowLabel ~= false,
        callback = function(checked) db.ShowLabel = checked; ApplySettings() end,
    })
    row2b:AddWidget(showLabelCheck, 0.5)
    manager:Register(showLabelCheck, "all")

    local labelColorPicker = GUIFrame:CreateColorPicker(row2b, "Label Color", {
        color = db.LabelColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.LabelColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2b:AddWidget(labelColorPicker, 0.5)
    manager:Register(labelColorPicker, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    -- Show Timer + Timer Color (paired)
    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local showTimerCheck = GUIFrame:CreateCheckbox(row2c, "Show Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked) db.ShowTimer = checked; ApplySettings() end,
    })
    row2c:AddWidget(showTimerCheck, 0.5)
    manager:Register(showTimerCheck, "all")

    local timerColorPicker = GUIFrame:CreateColorPicker(row2c, "Timer Color", {
        color = db.TimerColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TimerColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2c:AddWidget(timerColorPicker, 0.5)
    manager:Register(timerColorPicker, "all")
    card2:AddRow(row2c, Theme.rowHeight)

    -- Label Text editbox
    local row2d = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local labelEdit = GUIFrame:CreateEditBox(row2d, "Label Text", {
        value = db.LabelText or "INNERVATE",
        callback = function(val)
            db.LabelText = (val ~= "" and val) or "INNERVATE"
            ApplySettings()
        end,
    })
    row2d:AddWidget(labelEdit, 1)
    manager:Register(labelEdit, "all")
    card2:AddRow(row2d, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Font Settings (face + outline + label font size)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontSize    = "LabelFontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 32 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end

    ----------------------------------------------------------------
    -- Card 3b: Timer Font Size (separate — label and timer sized
    -- independently; face/outline shared via Card 3 above)
    ----------------------------------------------------------------
    local timerSizeCard = GUIFrame:CreateCard(scrollChild, "Timer Font Size", fontOffset)
    manager:Register(timerSizeCard, "all")

    local rowTS = GUIFrame:CreateRow(timerSizeCard.content, Theme.rowHeightLast)
    local timerSizeSlider = GUIFrame:CreateSlider(rowTS, "Timer Font Size", {
        min = 8, max = 32, step = 1,
        value = db.TimerFontSize or 18,
        callback = function(val) db.TimerFontSize = val; ApplySettings() end,
    })
    rowTS:AddWidget(timerSizeSlider, 1)
    manager:Register(timerSizeSlider, "all")
    timerSizeCard:AddRow(rowTS, Theme.rowHeightLast, 0)

    yOffset = timerSizeCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset, glowWidgets = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        db = db,
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    if glowWidgets then manager:RegisterGroup(glowWidgets, "all") end
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 5: Sound Settings
    ----------------------------------------------------------------
    local soundCard, soundOffset = GUIFrame:CreateSoundSettingsCard(scrollChild, yOffset, {
        db = db,
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    ----------------------------------------------------------------
    -- Card 6: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            local IT = GetModule()
            if IT then IT:ApplyPosition() end
        end,
    })
    manager:Register(posCard, "all")
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    yOffset = posOffset

    UpdateAllWidgetStates()

    return yOffset
end)
