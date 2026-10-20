-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DivineArbiter.lua                                   ║
-- ║  GUI: Divine Arbiter                                     ║
-- ║  Purpose: Configuration panel for the DivineArbiter      ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DivineArbiter", true)
    end
    return nil
end

local function RefreshPage()
    GUIFrame:RefreshContent()
end

GUIFrame:RegisterContent("DivineArbiter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DivineArbiter
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local DA = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("timer", function() return db.ShowTimer ~= false end)

    local function ApplySettings()
        if DA and DA.ApplySettings then DA:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not DA then return end
        DA.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DivineArbiter")
        else
            KitnEssentials:DisableModule("DivineArbiter")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Divine Arbiter", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    card1:AddLabel("Shows which spender consumes your Divine Arbiter buff (Retribution tier set) " ..
        "and how long you have to use it. Retribution Paladins only; the preview shows only " ..
        "while you are Retribution.")

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Display
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", {
        min = 20, max = 100, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSizeSlider, 1)
    manager:Register(iconSizeSlider, "all")
    card2:AddRow(row2a, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2b: Glow
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateAuraGlowCard(scrollChild, yOffset, {
        title = "Glow",
        db = db,
        onChangeCallback = ApplySettings,
        -- Pixel shows a row of controls the other styles do not; the cards
        -- below sit at fixed offsets, so the page is rebuilt.
        onHeightChange = function() C_Timer.After(0, RefreshPage) end,
    })
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Timer Display
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Timer Display", yOffset)
    manager:Register(card4, "all")

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local showTimerCheck = GUIFrame:CreateCheckbox(row4, "Show Countdown Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked)
            db.ShowTimer = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4:AddWidget(showTimerCheck, 0.5)
    manager:Register(showTimerCheck, "all")

    local timerColorPicker = GUIFrame:CreateColorPicker(row4, "Timer Color", {
        color = db.TimerTextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TimerTextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4:AddWidget(timerColorPicker, 0.5)
    manager:Register(timerColorPicker, "timer")
    card4:AddRow(row4, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Timer Font
    ----------------------------------------------------------------
    local timerFontCard, timerFontOffset, timerFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Timer Font",
        db = db,
        dbKeys = {
            fontFace = "TimerFontFace",
            fontSize = "TimerFontSize",
            fontOutline = "TimerFontOutline",
        },
        fontSizeRange = { 8, 36 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(timerFontCard, "timer")
    if timerFontWidgets then
        manager:RegisterGroup(timerFontWidgets, "timer")
    end
    yOffset = timerFontOffset

    ----------------------------------------------------------------
    -- Card 6: Sound
    ----------------------------------------------------------------
    local soundCard, soundOffset = GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {
        title = "Sound",
        db = db,
        dbKeys = { enabled = "SoundEnabled", name = "SoundName" },
        soundLabel = "Buff Sound",
        testChannel = "Master",
        notes = { "Plays once when either Divine Arbiter buff starts, on the Master channel." },
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    RefreshStates()
    return yOffset
end)
