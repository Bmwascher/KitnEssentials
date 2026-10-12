-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyPotions.lua                                    ║
-- ║  GUI: Party Cooldowns, Potions tab                       ║
-- ║  Purpose: party potion bars and the potion list.         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

local C_Timer = C_Timer
local next = next
local tostring = tostring

local GROW_OPTIONS = {
    { key = "DOWN", text = "Down" },
    { key = "UP",   text = "Up" },
}

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("PartyBuffs", true) end

GUIFrame:RegisterContent("PartyBuffsPotions", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PartyBuffs
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end
    db.ListPotions = db.ListPotions or {}

    local PB = GetModule()
    local Sensor = KE.PartyCooldownsSensor
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if PB and PB.ApplySettings then PB:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    local function RebuildPage()
        if GUIFrame.RefreshContent then
            C_Timer.After(0, function() GUIFrame:RefreshContent() end)
        end
    end

    -- Without the sensor file no bar can exist; the list still feeds the
    -- Cooldowns tab's while-active potion icons.
    manager:SetCondition("sensorOn", function() return Sensor ~= nil end)
    manager:SetCondition("barsOn", function() return Sensor ~= nil and db.PotionBars == true end)

    local function AddCheck(row, label, key, state, tooltip, onChange)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if onChange then onChange() end
            end,
            tooltip = tooltip,
        })
        row:AddWidget(check, 0.5)
        manager:Register(check, state)
    end

    local function AddSlider(row, label, key, low, high)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = low, max = high, step = 1,
            value = db[key],
            callback = function(val) db[key] = val; ApplySettings() end,
        })
        row:AddWidget(slider, 0.5)
        manager:Register(slider, "barsOn")
    end

    ----------------------------------------------------------------
    -- Card: Potion Bars
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Potion Bars", yOffset)
    if not Sensor then
        cardBars:AddNote("Potion bars need party cooldown timers, which this client cannot show.")
    elseif Sensor.door and not Sensor.DoorOpen() then
        cardBars:AddNote("Potion timers for party members are unavailable on this client.")
    end
    if next(KE.AuraRules.BuildIncludeSpellIDs(db.ListPotions)) == nil then
        cardBars:AddNote("No potion on the list is switched on, so no bar can start.")
    end
    cardBars:AddLabel("Move the bars with /kes edit.")
    cardBars:AddLabel("Healing potions are not shown: they leave no buff to see, and they have their own cooldown.")
    local rowB1 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeight)
    AddCheck(rowB1, "Potion Bars", "PotionBars", "sensorOn", nil, RefreshStates)
    AddCheck(rowB1, "Include Yourself", "PotionIncludeSelf", "barsOn", "Shows a bar for your own potions too.")
    cardBars:AddRow(rowB1, Theme.rowHeight)
    local rowB2 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeightLast)
    AddCheck(rowB2, "Show Ready Bars", "PotionShowReady", "barsOn",
        "Keeps a full bar reading Ready for each party member whose potion is ready.")
    local box
    box = GUIFrame:CreateEditBox(rowB2, "Potion Cooldown (sec)", {
        value = tostring(db.PotionSeconds),
        callback = function(text)
            local value = KE.PartyCooldownsRules.ClampSeconds(text)
            if not value then
                box:SetValue(tostring(db.PotionSeconds))
                return
            end
            box:SetValue(tostring(value))
            if value ~= db.PotionSeconds then
                db.PotionSeconds = value
                ApplySettings()
            end
        end,
    })
    rowB2:AddWidget(box, 0.5)
    manager:Register(box, "barsOn")
    cardBars:AddRow(rowB2, Theme.rowHeightLast, 0)
    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Bar Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Bar Display", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local grow = GUIFrame:CreateDropdown(rowD1, "Grow", {
        options = GROW_OPTIONS,
        value = db.PotionGrowth,
        callback = function(choice) db.PotionGrowth = choice; ApplySettings() end,
    })
    rowD1:AddWidget(grow, 0.5)
    manager:Register(grow, "barsOn")
    AddSlider(rowD1, "Width", "PotionWidth", 80, 400)
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD2, "Height", "PotionHeight", 10, 50)
    AddSlider(rowD2, "Spacing", "PotionSpacing", 0, 20)
    cardDisplay:AddRow(rowD2, Theme.rowHeight)
    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddCheck(rowD3, "Icon", "PotionShowIcon", "barsOn")
    AddCheck(rowD3, "Timer Text", "PotionShowTimer", "barsOn")
    cardDisplay:AddRow(rowD3, Theme.rowHeight)
    local rowD4 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    AddSlider(rowD4, "Text Size", "PotionTextSize", 8, 30)
    cardDisplay:AddRow(rowD4, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Potion List (live without Potion Bars: the Cooldowns tab's
    -- while-active potion icons read it too)
    ----------------------------------------------------------------
    local _, listOffset = GUIFrame:CreateAuraAllowlistCard(scrollChild, yOffset, {
        title = "Potion List",
        allowlist = db.ListPotions,
        getDefaults = function() return KE.PartyCooldownsPage.ShippedList("ListPotions") end,
        infoTitle = "Spell List Info",
        infoText = "A potion on this list starts a party member's potion bar here, and shows while active " ..
            "on the Cooldowns tab when Potions is ticked there. Only potions that put a buff on the drinker " ..
            "can be seen.",
        restoreActions = { { label = "Kitn Defaults" } },
        -- Every committed list change clears every potion bar, even one whose
        -- potions did not change. The Potion Bars card says when nothing is
        -- switched on, so a change also rebuilds the page.
        onChangeCallback = function()
            if KE.PartyPotions then KE.PartyPotions.ClearAll() end
            ApplySettings()
            RebuildPage()
        end,
    })
    yOffset = listOffset

    RefreshStates()
    return yOffset
end)
