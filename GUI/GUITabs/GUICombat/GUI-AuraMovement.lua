-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraMovement.lua                                    ║
-- ║  GUI: Aura Movement                                      ║
-- ║  Purpose: Configuration panel for the AuraMovement       ║
-- ║           module (movement buff display).                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraMovement", true) end

GUIFrame:RegisterContent("AuraMovement", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraMovement
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AM = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AM and AM.ApplySettings then AM:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraMovement", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraMovement")
        else
            KitnEssentials:DisableModule("AuraMovement")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- "Reverse Cooldown Direction" only matters when Swipe is on, so it's
    -- greyed out when Swipe is unchecked.
    manager:SetCondition("swipeOn", function() return db.Swipe ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Movement Buffs", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        ApplyModuleState(checked)
        KE:Print("Movement Buffs: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType  = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint        = "AnchorFrom",
            anchorPoint      = "AnchorTo",
            xOffset          = "XOffset",
            yOffset          = "YOffset",
            strata           = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        onChangeCallback    = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 45,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3a, "Icon Spacing", {
        min = 0, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row3a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row3b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 3,
        callback = function(val) db.IconsPerRow = val; ApplySettings() end,
    })
    row3b:AddWidget(iconsPerRowSlider, 0.5)
    manager:Register(iconsPerRowSlider, "all")

    local maxRowsSlider = GUIFrame:CreateSlider(row3b, "Max Rows", {
        min = 1, max = 3, step = 1,
        value = db.MaxRows or 1,
        callback = function(val) db.MaxRows = val; ApplySettings() end,
    })
    row3b:AddWidget(maxRowsSlider, 0.5)
    manager:Register(maxRowsSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    -- Separator between sliders and grow-direction dropdowns
    local row3sep1 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3a = GUIFrame:CreateSeparator(row3sep1)
    row3sep1:AddWidget(sep3a, 1)
    manager:Register(sep3a, "all")
    card3:AddRow(row3sep1, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local growHorizDropdown = GUIFrame:CreateDropdown(row3c, "Grow Horizontal", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowHorizontal or "LEFT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row3c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row3c, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "UP",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row3c:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeight)

    -- Separator between grow-direction dropdowns and swipe/reverse checkboxes
    local row3sep2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3b = GUIFrame:CreateSeparator(row3sep2)
    row3sep2:AddWidget(sep3b, 1)
    manager:Register(sep3b, "all")
    card3:AddRow(row3sep2, Theme.rowHeightSeparator)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local swipeCheck = GUIFrame:CreateCheckbox(row3d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
            RefreshStates()  -- re-evaluate swipeOn condition for reverseCheck
        end,
    })
    row3d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local reverseCheck = GUIFrame:CreateCheckbox(row3d, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row3d:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "swipeOn")
    card3:AddRow(row3d, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Allowlist
    ----------------------------------------------------------------
    local function GetMovementDefaults()
        if not KE.GetDefaultDB then return {} end
        local root = KE:GetDefaultDB()
        local section = root and root.profile and root.profile.AuraMovement
        return (section and section.Allowlist) or {}
    end

    db.Allowlist = db.Allowlist or {}

    local allowlistCard, allowlistOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
        title = "Allowlist",
        allowlist = db.Allowlist,
        getDefaults = GetMovementDefaults,
        infoTitle = "Allowlist Info",
        infoText = "This list decides which movement buffs the display shows. Personal and externally applied helpful buffs share this one list. A spell that is not on it, or whose row is switched off, will not appear.",
        restoreActions = {
            { label = "Kitn Defaults" },
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(allowlistCard, "all")
    yOffset = allowlistOffset

    ----------------------------------------------------------------
    -- Card 5: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset, glowWidgets = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow",
        db = db,
        dbKeys = {
            enabled   = "GlowEnabled",
            type      = "GlowType",
            color     = "GlowColor",
            lines     = "GlowLines",
            frequency = "GlowFrequency",
            length    = "GlowLength",
            thickness = "GlowThickness",
            border    = "GlowBorder",
            scale     = "GlowScale",
            startAnim = "GlowStartAnim",
            duration  = "GlowDuration",
        },
        types = {
            { key = "pixel",    text = "Pixel" },
            { key = "ants",     text = "Ants" },
            { key = "procloop", text = "Proc Loop" },
            { key = "alert",    text = "Alert" },
        },
        resolveType = KE.AuraGlowRules.ResolveType,
        typeTooltip = "Pixel plays four animations for every icon, more than any other style. In testing it ran about 2% slower than Ants at two icons, and about 7% slower at thirty-six icons, twelve per row across three rows.",
        typeRows = function(rows)
            return {
                pixel       = rows.pixel,
                unsupported = rows.pixelExtras,
                autocast    = rows.autocast,
                proc        = rows.proc,
            }
        end,
        showSpeed = function() return true end,
        speedAdapter = {
            read = function(readDb, readKeys)
                return KE.AuraGlowRules.NormaliseFrequency(
                    KE.AuraGlowRules.ReadSpeed(readDb, readKeys), 0.05, 2)
            end,
            write   = KE.AuraGlowRules.WriteSpeed,
            setType = KE.AuraGlowRules.SetType,
            min     = 0.05,
            max     = 2,
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    if glowWidgets then
        manager:RegisterGroup(glowWidgets, "all")
    end
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 6: Sound
    ----------------------------------------------------------------
    local soundCard, soundOffset = GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {
        title = "Sound",
        db = db,
        dbKeys = { enabled = "SoundEnabled", name = "SoundName" },
        notes = {
            "Plays for any enabled spell on the Allowlist above, whether you cast it or another player does.",
            "Allowlist changes made inside a dungeon or raid take effect when you leave. The sound stays silent until then.",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    ----------------------------------------------------------------
    -- Card 7: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Timer Size",  dbKey = "TimerFontSize", default = 18 },
        },
        fontSizeRange = { 8, 48 },
        extraSlider = {
            label = "Show Decimals Below (sec)",
            dbKey = "DecimalThreshold",
            min = 0, max = 10, step = 1,
            value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        },
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
