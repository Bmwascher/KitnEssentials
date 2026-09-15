-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PIAssist.lua                                        ║
-- ║  GUI: Power Infusion Assist                              ║
-- ║  Purpose: Configuration panel for the PIAssist module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PIAssist", true)
    end
    return nil
end

local function GetMacroModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PIMacroBuilder", true)
    end
    return nil
end

GUIFrame:RegisterContent("PIAssist", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PIAssist
    if not db then return yOffset end

    local PA = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PA and PA.ApplySettings then PA:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not PA then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("PIAssist")
        else KitnEssentials:DisableModule("PIAssist") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Power Infusion Assist", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Power Infusion Assist: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightNote)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Priest only. Glows the raid frame of the player your PI macro targets while their burst cooldown is running.\n" ..
        KE:ColorTextByTheme("-") .. " The game matches the buff and draws the glow; nothing a fight hides is read.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeightNote, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Target
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Target", yOffset)
    manager:Register(card2, "all")

    -- What the glow follows is the module's answer, not the stored name:
    -- with PI Macro Builder on they differ until the macro carries it.
    local macroDb = KE.db.profile.PIMacroBuilder
    local stored = macroDb and macroDb.Target
    if type(stored) ~= "string" or stored == "" then stored = nil end
    local watching = PA and PA.TargetName and PA:TargetName() or nil
    local line
    if watching then
        line = "Watching |cffffd100" .. watching .. "|r."
        if stored ~= watching then
            line = line .. " |cff888888The macro has not caught up with "
                .. (stored and ("\"" .. stored .. "\"") or "the cleared target") .. " yet.|r"
        end
    elseif stored then
        line = "|cff888888" .. stored .. " is stored; the glow waits for the macro to carry it.|r"
    else
        line = "|cff888888No target set.|r"
    end
    card2:AddLabel(line)

    local targetNoteRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightNote)
    local targetNote = GUIFrame:CreateText(targetNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Use " .. KE:ColorTextByTheme("/kitn pi") .. " while hovering or targeting a player. It rewrites the PI macro and points the glow at the same person.\n" ..
        KE:ColorTextByTheme("-") .. " Both need the " .. KE:ColorTextByTheme("Priest: PI Macro") .. " tab switched on; the name can also be typed there.",
        50, "hide")
    targetNoteRow:AddWidget(targetNote, 1)
    card2:AddRow(targetNoteRow, Theme.rowHeightNote)

    local clearRow = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local clearButton = GUIFrame:CreateButton(clearRow, "Clear Target", {
        width = 160,
        height = 26,
        callback = function()
            local macro = GetMacroModule()
            if macro and macro.SetTarget then macro:SetTarget(nil) end
        end,
    })
    clearRow:AddWidget(clearButton, 1)
    manager:Register(clearButton, "all")
    card2:AddRow(clearRow, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Options
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Options", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local healerCheck = GUIFrame:CreateCheckbox(row3a, "Healers Only", {
        value = db.HealersOnly ~= false,
        tooltip = "Only active as Discipline or Holy. Off, a Shadow Priest gets it too.",
        callback = function(checked) db.HealersOnly = checked; ApplySettings() end,
    })
    row3a:AddWidget(healerCheck, 0.5)
    manager:Register(healerCheck, "all")

    local readyCheck = GUIFrame:CreateCheckbox(row3a, "Only While PI Is Ready", {
        value = db.OnlyWhenPIReady ~= false,
        tooltip = "After you cast Power Infusion the glow stays off until it is back. Timed from PI's base cooldown, from the casts seen while the module is active; a cooldown already running when you log in or switch the module on is not seen, and cooldown reduction is not seen. The Grace slider trims it.",
        callback = function(checked) db.OnlyWhenPIReady = checked; ApplySettings() end,
    })
    row3a:AddWidget(readyCheck, 0.5)
    manager:Register(readyCheck, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local graceSlider = GUIFrame:CreateSlider(row3b, "Grace (seconds)", {
        min = 0, max = 15, step = 1,
        value = db.Grace or 0,
        tooltip = "Lets the glow return this many seconds before Power Infusion is actually up, so you are ready on the button.",
        callback = function(val) db.Grace = val; ApplySettings() end,
    })
    row3b:AddWidget(graceSlider, 1)
    manager:Register(graceSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Tracked Cooldowns (allowlist)
    ----------------------------------------------------------------
    local function GetShippedAllowlist()
        if not KE.GetDefaultDB then return {} end
        local root = KE:GetDefaultDB()
        local section = root and root.profile and root.profile.PIAssist
        return (section and section.Allowlist) or {}
    end

    db.Allowlist = db.Allowlist or {}

    local allowlistCard, allowlistOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
        title = "Tracked Cooldowns",
        allowlist = db.Allowlist,
        getDefaults = GetShippedAllowlist,
        infoTitle = "Tracked Cooldowns Info",
        infoText = "The buffs that count as a burst. The glow shows while the target carries any enabled one; a spell that is not on the list, or whose row is switched off, never glows. Add a spell id for a cooldown the list is missing.",
        restoreActions = {
            { label = "Kitn Defaults" },
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(allowlistCard, "all")
    yOffset = allowlistOffset

    ----------------------------------------------------------------
    -- Card 5: Glow (engine card; Pulse Border only)
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
            pulse     = "GlowPulse",
        },
        types = {
            { key = "border", text = "Pulse Border" },
        },
        resolveType = KE.AuraGlowRules.ResolveType,
        typeTooltip = "A border around the target's raid frame while their burst buff is up. Colour and thickness edits made inside a dungeon or raid take effect when you leave.",
        typeRows = function(rows)
            return {
                border      = rows.border,
                pixel       = rows.pixel,
                unsupported = rows.pixelExtras,
                autocast    = rows.autocast,
                proc        = rows.proc,
            }
        end,
        showSpeed = function() return false end,
        speedAdapter = {
            read = function(readDb, readKeys)
                return KE.AuraGlowRules.NormaliseFrequency(
                    KE.AuraGlowRules.ReadSpeed(readDb, readKeys), 0.05, 1)
            end,
            write   = KE.AuraGlowRules.WriteSpeed,
            setType = KE.AuraGlowRules.SetType,
            min     = 0.05,
            max     = 1,
        },
        onChangeCallback = ApplySettings,
    })
    -- The card alone: its SetEnabled already manages the controls under it
    -- against the glow switch, and a second registration of those controls
    -- would re-enable them after the card had switched them off.
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 6: Sound
    ----------------------------------------------------------------
    local soundCard, soundOffset = GUIFrame:CreateAuraApplicationSoundCard(scrollChild, yOffset, {
        title = "Sound",
        db = db,
        dbKeys = { enabled = "SoundEnabled", name = "SoundName" },
        notes = {
            "Plays when the target gains any enabled Tracked Cooldown, whoever applied it.",
            "Changes made inside a dungeon or raid take effect when you leave. The sound stays silent until then.",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(soundCard, "all")
    yOffset = soundOffset

    RefreshStates()
    return yOffset
end)
