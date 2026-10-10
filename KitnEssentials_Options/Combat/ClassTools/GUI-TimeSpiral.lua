-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TimeSpiral.lua                                      ║
-- ║  GUI: Time Spiral Tracker                                ║
-- ║  Purpose: Configuration panel for the TimeSpiral module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("TimeSpiral", true)
    end
    return nil
end

local function RefreshPage()
    GUIFrame:RefreshContent()
end

GUIFrame:RegisterContent("TimeSpiral", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TimeSpiral
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local TSP = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("text",  function() return db.ShowText    ~= false end)
    manager:SetCondition("timer", function() return db.ShowTimer   ~= false end)

    local function ApplySettings()
        if TSP and TSP.ApplySettings then TSP:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not TSP then return end
        TSP.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("TimeSpiral")
        else
            KitnEssentials:DisableModule("TimeSpiral")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Time Spiral Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    card1:AddLabel("Shows when an Evoker's Time Spiral has given you a free use of your movement " ..
        "ability, and how long you have to spend it. Works for every class.")

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
    local glowCard, glowOffset = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow",
        db = db,
        dbKeys = {
            enabled   = "GlowEnabled",
            type      = "GlowType",
            color     = "GlowColor",
            lines     = "GlowLines",
            frequency = "GlowFrequency",
            thickness = "GlowThickness",
            duration  = "GlowDuration",
        },
        types = {
            { key = "pixel",    text = "Pixel" },
            { key = "ants",     text = "Ants" },
            { key = "procloop", text = "Proc Loop" },
            { key = "alert",    text = "Alert" },
        },
        resolveType = KE.AuraGlowRules.ResolveType,
        -- Length and Border need a Lua-driven pixel glow; the engine's is not.
        typeRows = function(rows)
            return {
                pixel       = rows.pixel,
                unsupported = rows.pixelExtras,
                autocast    = rows.autocast,
                proc        = rows.proc,
                border      = rows.border,
            }
        end,
        showSpeed = function() return true end,
        -- SetType, not a plain write: a stored "proc" keeps its loop speed in
        -- GlowDuration, and a plain write would drop it.
        speedAdapter = {
            read = function(readDb, readKeys)
                return KE.AuraGlowRules.NormalizeFrequency(
                    KE.AuraGlowRules.ReadSpeed(readDb, readKeys), 0.05, 2)
            end,
            write   = KE.AuraGlowRules.WriteSpeed,
            setType = KE.AuraGlowRules.SetType,
            min     = 0.05,
            max     = 2,
        },
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
    -- Card 4: Label Text
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Label Text", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local showTextCheck = GUIFrame:CreateCheckbox(row4a, "Show Text Label", {
        value = db.ShowText ~= false,
        callback = function(checked)
            db.ShowText = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(showTextCheck, 0.5)
    manager:Register(showTextCheck, "all")

    local textColorPicker = GUIFrame:CreateColorPicker(row4a, "Text Color", {
        color = db.TextColor or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(textColorPicker, 0.5)
    manager:Register(textColorPicker, "text")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local textLabelEdit = GUIFrame:CreateEditBox(row4b, "Text Label", {
        value = db.TextLabel or "FREE",
        callback = function(text) db.TextLabel = text; ApplySettings() end,
    })
    row4b:AddWidget(textLabelEdit, 1)
    manager:Register(textLabelEdit, "text")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Label Font
    ----------------------------------------------------------------
    local labelFontCard, labelFontOffset, labelFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Label Font",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 36 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(labelFontCard, "text")
    if labelFontWidgets then
        manager:RegisterGroup(labelFontWidgets, "text")
    end
    yOffset = labelFontOffset

    ----------------------------------------------------------------
    -- Card 6: Timer Display
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Timer Display", yOffset)
    manager:Register(card6, "all")

    local row6 = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local showTimerCheck = GUIFrame:CreateCheckbox(row6, "Show Countdown Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked)
            db.ShowTimer = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row6:AddWidget(showTimerCheck, 0.5)
    manager:Register(showTimerCheck, "all")

    local timerColorPicker = GUIFrame:CreateColorPicker(row6, "Timer Color", {
        color = db.TimerTextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TimerTextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6:AddWidget(timerColorPicker, 0.5)
    manager:Register(timerColorPicker, "timer")
    card6:AddRow(row6, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Timer Font
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
    -- Card 8: Sound
    ----------------------------------------------------------------
    local soundCard, soundOffset = GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {
        title = "Sound",
        db = db,
        dbKeys = { enabled = "SoundEnabled", name = "SoundName" },
        soundLabel = "Buff Sound",
        testChannel = "Master",
        notes = { "Plays once when you receive the Time Spiral buff, on the Master channel." },
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    RefreshStates()
    return yOffset
end)
