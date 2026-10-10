-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RaidNotifications.lua                               ║
-- ║  GUI: Raid Notifications                                 ║
-- ║  Purpose: Configuration panel for the RaidNotifications  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local GENERAL_ALERTS = {
    { dbKey = "GatewayEnabled",  label = "Gateway",             tooltip = "Shows when Demonic Gateway is usable." },
    { dbKey = "BenchEnabled",    label = "Benched",             tooltip = "Alerts when sitting in raid group 7 or 8 of a Mythic raid." },
    { dbKey = "VoidcoreEnabled", label = "Bonus Rolls Missing", tooltip = "Shows in a seasonal dungeon or raid while Nebulous Voidcore is below its cap. Hides in combat and inside a running key." },
}

local AUTO_READY = {
    { dbKey = "AutoReadyBenched", label = "Auto Ready When Benched", tooltip = "Clicks Ready for you on a raid ready check while you sit in raid group 7 or 8 outside any instance, and prints a line in chat. In combat, or on a check you started, it leaves the check to you." },
}

local BOSS_ALERTS = {
    { dbKey = "ResetBossEnabled", label = "Reset Boss", tooltip = "Reminder when a lust debuff is active between pulls." },
    { dbKey = "LootBossEnabled",  label = "Loot Boss",  tooltip = "Reminder to loot after a boss kill." },
}

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

    -- == true, not ~= false: the module never subscribes an alert whose key is nil.
    local function AddAlertRow(card, alerts)
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeight)
        for _, alert in ipairs(alerts) do
            local key = alert.dbKey
            local check = GUIFrame:CreateCheckbox(row, alert.label, {
                value = db[key] == true,
                callback = function(checked) db[key] = checked; ApplySettings() end,
                tooltip = alert.tooltip,
            })
            row:AddWidget(check, 1/3)
            manager:Register(check, "all")
        end
        card:AddRow(row, Theme.rowHeight)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Raid Notifications", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    card1:AddLabel("On-screen reminders for the moments a raid forgets. Hover an alert for what it watches.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local iconToggle = GUIFrame:CreateCheckbox(row1, "Show Icons", {
        value = db.ShowIcons ~= false,
        callback = function(checked) db.ShowIcons = checked; ApplySettings() end,
        tooltip = "Shows flavor icons alongside the alert text, for every alert.",
    })
    row1:AddWidget(iconToggle, 1/3)
    manager:Register(iconToggle, "all")
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Alerts
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Alerts", yOffset)
    manager:Register(card2, "all")

    AddAlertRow(card2, GENERAL_ALERTS)
    AddAlertRow(card2, AUTO_READY)
    card2:AddNote("Each alert stays up while its condition holds. Auto Ready When Benched shows no alert; it answers the ready check.")

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Boss Alerts
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Boss Alerts", yOffset)
    manager:Register(card3, "all")

    AddAlertRow(card3, BOSS_ALERTS)

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local durationSlider = GUIFrame:CreateSlider(row3, "Duration", {
        min = 5, max = 120, step = 1,
        value = db.AlertDuration or 40,
        callback = function(val) db.AlertDuration = val end,
        tooltip = "How long Reset Boss and Loot Boss stay up at most. Both also hide early on their own. The other alerts follow their condition and have no timer.",
    })
    row3:AddWidget(durationSlider, 1)
    manager:Register(durationSlider, "all")
    card3:AddRow(row3, Theme.rowHeight)

    card3:AddNote("The longest either stays up. Reset Boss also hides when combat starts or the lust debuff ends; Loot Boss when you loot or the next pull starts.")

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Position Settings
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
    -- Card 5: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "all",
        isLast     = true,
        colorMode  = { key = "ColorMode", onChange = RefreshStates },
        colors     = {
            { label = "Custom Color", key = "Color", default = { 0.969, 0.027, 0.945, 1 }, group = "customColor" },
        },
    })

    RefreshStates()
    return yOffset
end)
