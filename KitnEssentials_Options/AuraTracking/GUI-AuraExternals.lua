-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraExternals.lua                                   ║
-- ║  GUI: Aura Externals                                     ║
-- ║  Purpose: Configuration panel for the AuraExternals      ║
-- ║           module (external defensives display).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

-- Each client's examples name spells that client has.
local INTRO_TEXT, SELF_CAST_TOOLTIP, DEFENSIVES_TOOLTIP
if KE.IS_FOREVER then
    INTRO_TEXT = "Shows the external defensives other players put on you, Blessing of Protection and " ..
        "Blessing of Sacrifice and the like, as icons with a glow, and can include your own defensives too."
    SELF_CAST_TOOLTIP = "Shows only what other players put on you. Your own casts are hidden, which includes your own raid cooldowns such as Tranquility."
    DEFENSIVES_TOOLTIP = "Include your own large defensive cooldowns (Shield Wall, Divine Shield, etc.) alongside externally-applied defensives."
else
    INTRO_TEXT = "Shows the external defensives other players put on you, Pain Suppression and " ..
        "Ironbark and the like, as icons with a glow, and can include your own defensives too."
    SELF_CAST_TOOLTIP = "Shows only what other players put on you. Your own casts are hidden, which includes your own raid cooldowns such as Rallying Cry or Aura Mastery."
    DEFENSIVES_TOOLTIP = "Include your own large defensive cooldowns (Shield Wall, Iron Bark, etc.) alongside externally-applied defensives."
end

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraExternals", true) end

local function RefreshPage()
    GUIFrame:RefreshContent()
end

GUIFrame:RegisterContent("AuraExternals", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraExternals
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AX = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AX and AX.ApplySettings then AX:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraExternals", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraExternals")
        else
            KitnEssentials:DisableModule("AuraExternals")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- "Reverse Cooldown Direction" only matters when Swipe is on, so it's
    -- grayed out when Swipe is unchecked.
    manager:SetCondition("swipeOn", function() return db.Swipe ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Externals", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        ApplyModuleState(checked)
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    card1:AddLabel(INTRO_TEXT)
    yOffset = card1:GetNextOffset()

    local cardTracked = GUIFrame:CreateCard(scrollChild, "Tracked Auras", yOffset)
    manager:Register(cardTracked, "all")

    local row1b = GUIFrame:CreateRow(cardTracked.content, Theme.rowHeightLast)
    local selfCastCheck = GUIFrame:CreateCheckbox(row1b, "Hide Buffs You Cast Yourself", {
        value = db.HideSelfCast == true,
        callback = function(checked)
            db.HideSelfCast = checked
            ApplySettings()
            RefreshStates()  -- re-evaluate casterOwn for Hide My Own Name
        end,
        tooltip = SELF_CAST_TOOLTIP,
    })
    row1b:AddWidget(selfCastCheck, 0.5)
    manager:Register(selfCastCheck, "all")

    local defensivesCheck = GUIFrame:CreateCheckbox(row1b, "Include Defensives", {
        value = db.ShowBigDefensives ~= false,
        callback = function(checked) db.ShowBigDefensives = checked; ApplySettings() end,
        tooltip = DEFENSIVES_TOOLTIP,
    })
    row1b:AddWidget(defensivesCheck, 0.5)
    manager:Register(defensivesCheck, "all")

    cardTracked:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = cardTracked:GetNextOffset()

    local casterCard, casterOffset = GUIFrame:CreateAuraCasterNameCard(scrollChild, yOffset, {
        title = "Caster Name",
        db = db,
        -- Your own casts are already hidden, so there is no own name to hide.
        ownNameBlocked = function() return db.HideSelfCast == true end,
        onChangeCallback = ApplySettings,
    })
    manager:Register(casterCard, "all")
    yOffset = casterOffset

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
        value = db.IconSize or 36,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3a, "Icon Spacing", {
        min = -1, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row3a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row3b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 6,
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
        options = GUIFrame.GrowHorizontalOptions,
        value = db.GrowHorizontal or "RIGHT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row3c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row3c, "Grow Vertical", {
        options = GUIFrame.GrowVerticalOptions,
        value = db.GrowVertical or "DOWN",
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
    -- Card 4: Glow
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateAuraGlowCard(scrollChild, yOffset, {
        title = "Glow",
        db = db,
        -- Measured, not guessed. Ants and Proc Loop each play two animations
        -- per icon, the main flipbook and its additive overlay; Alert plays
        -- one; Pixel plays four, one per edge.
        typeTooltip = "Pixel plays four animations for every icon, more than any other style. In testing it ran about 2% slower than Ants at two icons, and about 7% slower at thirty-six icons, twelve per row across three rows.",
        onChangeCallback = ApplySettings,
        onHeightChange = function() C_Timer.After(0, RefreshPage) end,
    })
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    local function GetShippedAllowlist()
        if not KE.GetDefaultDB then return {} end
        local root = KE:GetDefaultDB()
        local section = root and root.profile and root.profile.AuraExternals
        return (section and section.Allowlist) or {}
    end

    db.Allowlist = db.Allowlist or {}

    local allowlistCard, allowlistOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
        title = "Allowlist",
        allowlist = db.Allowlist,
        getDefaults = GetShippedAllowlist,
        infoTitle = "Allowlist Info",
        infoText = "This list decides which buffs the display shows. A spell that is not on it, or whose row is switched off, will not appear. Only helpful auras on yourself can be filtered this way, which is every external defensive.",
        restoreActions = {
            { label = "Kitn Defaults" },
            {
                label = "Blizzard Flagged",
                tooltip = "Enables only the spells this client flags as external defensives, and switches the rest off without deleting them. This reads the game's per-spell flag, which can differ from what Blizzard's own external defensives frame shows.",
                resolveEnabled = function(spellID)
                    local ok, flagged = pcall(C_Spell.IsExternalDefensive, spellID)
                    return ok and flagged
                end,
            },
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(allowlistCard, "all")
    yOffset = allowlistOffset

    local soundCard, soundOffset = GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {
        title = "Sound",
        db = db,
        dbKeys = { enabled = "SoundEnabled", name = "SoundName" },
        notes = {
            -- Says "including your own" because the sound CANNOT honor
            -- HideSelfCast. Blizzard's UnitAuraSoundInfo carries a unit and a
            -- spell id and no caster field, so a registration fires for the
            -- spell however it was applied. The display filters on the caster;
            -- the sound cannot.
            "Plays for any enabled spell on the Allowlist above, including ones you cast on yourself.",
            -- Not a caution about the GUI but about the sound registry:
            -- removing a registration is always allowed, adding one is not
            -- while aura identities are hidden, so an Allowlist edit made in
            -- there retires the old set and cannot build the new one until the
            -- restriction lifts.
            "Allowlist changes made inside a dungeon or raid take effect when you leave. The sound stays silent until then.",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local fontCard, _, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Count Size",  dbKey = "FontSize",      default = 14 },
            { label = "Timer Size",  dbKey = "TimerFontSize", default = 18 },
        },
        fontSizeRange = { 8, 48 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end

    -- The card's own last row is added with no trailing gap, so re-open the
    -- spacing before appending to it.
    fontCard:AddSpacing(Theme.paddingSmall)

    local decimalRow = GUIFrame:CreateRow(fontCard.content, Theme.rowHeightLast)
    local decimalSlider = GUIFrame:CreateSlider(decimalRow, "Show Decimals Below (sec)", {
        min = 0, max = 10, step = 1,
        value = KE.AuraRules.NormalizeDecimalThreshold(db.DecimalThreshold),
        callback = function(val) db.DecimalThreshold = val; ApplySettings() end,
    })
    decimalRow:AddWidget(decimalSlider, 0.5)
    manager:Register(decimalSlider, "all")
    fontCard:AddRow(decimalRow, Theme.rowHeightLast, 0)

    yOffset = fontCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Overlay Position
    --
    -- One anchor per element (Timer text / Stack text) drives both
    -- AnchorFrom and AnchorTo — picking "CENTER" aligns the element's
    -- center with the button's center, picking "BOTTOMRIGHT" stacks them
    -- by bottom-right, etc. Mirrors AuraDebuffs' Overlay Position card.
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Overlay Position", yOffset)
    manager:Register(card7, "all")

    local TEXT_ANCHOR_OPTIONS = GUIFrame.AnchorPointOptions

    db.TimerPosition = db.TimerPosition or {}
    db.StackPosition = db.StackPosition
        or { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = -1, YOffset = 1 }
    local tp, sp = db.TimerPosition, db.StackPosition

    -- Row: Timer Anchor + Timer X + Timer Y (each 1/3 width)
    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local timerAnchor = GUIFrame:CreateDropdown(row7a, "Timer Text Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = tp.AnchorFrom or "CENTER",
        callback = function(key)
            tp.AnchorFrom = key
            tp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7a:AddWidget(timerAnchor, 1 / 3)
    manager:Register(timerAnchor, "all")

    local timerX = GUIFrame:CreateSlider(row7a, "Timer X", {
        min = -50, max = 50, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) tp.XOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerX, 1 / 3)
    manager:Register(timerX, "all")

    local timerY = GUIFrame:CreateSlider(row7a, "Timer Y", {
        min = -50, max = 50, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) tp.YOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerY, 1 / 3)
    manager:Register(timerY, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    -- Separator between Timer and Stack rows
    local row7sep = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    manager:Register(sep7, "all")
    card7:AddRow(row7sep, Theme.rowHeightSeparator)

    -- Row: Stack Anchor + Stack X + Stack Y (each 1/3 width)
    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local stackAnchor = GUIFrame:CreateDropdown(row7b, "Stack Count Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = sp.AnchorFrom or "BOTTOMRIGHT",
        callback = function(key)
            sp.AnchorFrom = key
            sp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7b:AddWidget(stackAnchor, 1 / 3)
    manager:Register(stackAnchor, "all")

    local stackX = GUIFrame:CreateSlider(row7b, "Stack X", {
        min = -50, max = 50, step = 1,
        value = sp.XOffset or -1,
        callback = function(val) sp.XOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackX, 1 / 3)
    manager:Register(stackX, "all")

    local stackY = GUIFrame:CreateSlider(row7b, "Stack Y", {
        min = -50, max = 50, step = 1,
        value = sp.YOffset or 1,
        callback = function(val) sp.YOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackY, 1 / 3)
    manager:Register(stackY, "all")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)
