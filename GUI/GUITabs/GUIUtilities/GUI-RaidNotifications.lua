-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RaidNotifications.lua                               ║
-- ║  GUI: Raid Notifications                                 ║
-- ║  Purpose: Configuration panel for the RaidNotifications  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("RaidNotifications", true)
    end
    return nil
end

GUIFrame:RegisterContent("RaidNotifications", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RaidNotifications
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("RaidNotifications")
        else
            KitnEssentials:DisableModule("RaidNotifications")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Raid Notifications", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Raid Notifications", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Raid Notifications",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Alert Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    manager:Register(card2, "all")

    local accentDash = KE:ColorTextByTheme("—")
    local grey = "|cff888888"

    local alertTypes = {
        { dbKey = "GatewayEnabled",  label = "Gateway",     desc = "- Shows when Demonic Gateway is usable.",    default = true },
        { dbKey = "ResetBossEnabled", label = "Reset Boss",  desc = "- Reminder when lust debuff is active between pulls.", default = true },
        { dbKey = "LootBossEnabled",  label = "Loot Boss",   desc = "- Reminder to loot after a boss kill.",       default = true },
    }

    for _, alert in ipairs(alertTypes) do
        local row = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
        local checked = db[alert.dbKey] ~= false
        if alert.default == false then
            checked = db[alert.dbKey] == true
        end
        local check = GUIFrame:CreateCheckbox(row, alert.label .. "  " .. grey .. alert.desc .. "|r", {
            value = checked,
            callback = function(val) db[alert.dbKey] = val; ApplySettings() end,
        })
        row:AddWidget(check, 1)
        manager:Register(check, "all")
        card2:AddRow(row, Theme.rowHeight)
    end

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconToggle = GUIFrame:CreateCheckbox(row2b, "Show Icons  " .. grey .. "- Shows the spell icon alongside alert text.|r", {
        value = db.ShowIcons ~= false,
        callback = function(checked) db.ShowIcons = checked; ApplySettings() end,
    })
    row2b:AddWidget(iconToggle, 1)
    manager:Register(iconToggle, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local durationSlider = GUIFrame:CreateSlider(row2c, "Alert Duration", {
        min = 5, max = 120, step = 1,
        value = db.AlertDuration or 40,
        callback = function(val) db.AlertDuration = val end,
    })
    row2c:AddWidget(durationSlider, 1)
    manager:Register(durationSlider, "all")

    -- Inline descriptor: sits to the right of the slider's "Alert Duration" label,
    -- in the empty space above the slider bar (y=0 to y=-14ish).
    local durationDesc = row2c:CreateFontString(nil, "OVERLAY")
    durationDesc:SetPoint("LEFT", durationSlider.label, "RIGHT", 8, 0)
    KE:ApplyThemeFont(durationDesc, "small")
    durationDesc:SetTextColor(0x88 / 0xFF, 0x88 / 0xFF, 0x88 / 0xFF, 1)
    durationDesc:SetJustifyH("LEFT")
    durationDesc:SetText(accentDash .. " |cff888888Duration applies to Reset Boss and Loot Boss alerts.|r")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card5, "all")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "custom",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row5:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row5, "Custom Color", {
        color = db.Color or { 0.969, 0.027, 0.945, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
