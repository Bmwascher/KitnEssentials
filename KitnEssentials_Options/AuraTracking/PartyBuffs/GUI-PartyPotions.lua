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

local GROW_OPTIONS = GUIFrame.GrowVerticalOptions

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

    -- A color drag calls back on every mouse move.
    local function QueueApply()
        if PB and PB.QueueApplySettings then PB:QueueApplySettings() end
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
    manager:SetCondition("barsOn", function() return Sensor ~= nil and db.PotionBars == true end)
    -- Dark Mode sets the fill and both names itself.
    manager:SetCondition("lightBars", function()
        return Sensor ~= nil and db.PotionBars == true and db.PotionDarkMode ~= true
    end)
    manager:SetCondition("ownColors", function()
        return Sensor ~= nil and db.PotionBars == true and db.PotionClassBars ~= true and db.PotionDarkMode ~= true
    end)

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

    local function AddColor(row, label, key, state, tooltip)
        local picker = GUIFrame:CreateColorPicker(row, label, {
            color = db[key],
            callback = function(r, g, b, a)
                db[key] = { r, g, b, a }
                QueueApply()
            end,
            tooltip = tooltip,
        })
        row:AddWidget(picker, 0.5)
        manager:Register(picker, state)
    end

    ----------------------------------------------------------------
    -- Card: Potion Bars
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Potion Bars", yOffset)
    if Sensor then
        cardBars:AddHeaderToggle(db.PotionBars == true, function(checked)
            db.PotionBars = checked
            ApplySettings()
        end)
    end
    if not Sensor then
        cardBars:AddNote("Potion bars need party cooldown timers, which this client cannot show.")
    elseif Sensor.door and not Sensor.DoorOpen() then
        cardBars:AddNote("Potion timers for party members are unavailable on this client.")
    end
    if next(KE.AuraRules.BuildIncludeSpellIDs(db.ListPotions)) == nil then
        cardBars:AddNote("No potion on the list is switched on, so no bar can start.")
    end
    local rowB1 = GUIFrame:CreateRow(cardBars.content, Theme.rowHeightLast)
    AddCheck(rowB1, "Include Yourself", "PotionIncludeSelf", "barsOn", "Shows a bar for your own potions too.")
    AddCheck(rowB1, "Show Ready Bars", "PotionShowReady", "barsOn",
        "Keeps a bar reading Ready for each party member whose potion is ready.")
    cardBars:AddRow(rowB1, Theme.rowHeightLast, 0)
    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Bar Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Bar Display", yOffset)
    local rowD1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    AddSlider(rowD1, "Width", "PotionWidth", 80, 400)
    AddSlider(rowD1, "Height", "PotionHeight", 10, 50)
    cardDisplay:AddRow(rowD1, Theme.rowHeight)
    local rowD2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local grow = GUIFrame:CreateDropdown(rowD2, "Grow", {
        options = GROW_OPTIONS,
        value = db.PotionGrowth,
        callback = function(choice) db.PotionGrowth = choice; ApplySettings() end,
    })
    rowD2:AddWidget(grow, 0.5)
    manager:Register(grow, "barsOn")
    AddSlider(rowD2, "Spacing", "PotionSpacing", 0, 20)
    cardDisplay:AddRow(rowD2, Theme.rowHeight)
    local rowD3 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    AddCheck(rowD3, "Timer Text", "PotionShowTimer", "barsOn")
    AddSlider(rowD3, "Text Size", "PotionTextSize", 8, 30)
    cardDisplay:AddRow(rowD3, Theme.rowHeightLast, 0)
    yOffset = cardDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Colors
    ----------------------------------------------------------------
    local cardColors = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    local rowC0 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    AddCheck(rowC0, "Dark Mode", "PotionDarkMode", "barsOn",
        "Draws each bar in its player's class color on the Background Color, with the name white while the " ..
        "potion cools and in the class color once it is ready, and leaves a Ready bar empty. Class Color Bars, " ..
        "Class Color Names and Bar Color do not apply while it is on.",
        RefreshStates)
    cardColors:AddRow(rowC0, Theme.rowHeight)
    local rowC1 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    AddCheck(rowC1, "Class Color Bars", "PotionClassBars", "lightBars",
        "Draws each bar in its player's class color; the drained part takes the Background Color's opacity. " ..
        "Off: Bar Color and Background Color.",
        RefreshStates)
    AddCheck(rowC1, "Class Color Names", "PotionClassNames", "lightBars",
        "Writes each name in its player's class color instead of white.")
    cardColors:AddRow(rowC1, Theme.rowHeight)
    local rowC2 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeightLast)
    AddColor(rowC2, "Bar Color", "PotionBarColor", "ownColors")
    AddColor(rowC2, "Background Color", "PotionBgColor", "barsOn",
        "With Dark Mode off and Class Color Bars on, only its opacity is used. With Dark Mode on, it colors " ..
        "the drained part and fills the empty Ready bar.")
    cardColors:AddRow(rowC2, Theme.rowHeightLast, 0)
    yOffset = cardColors:GetNextOffset()

    ----------------------------------------------------------------
    -- Card: Position Settings (the same saved position /kes edit moves)
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = "PotionPosition",
        dbKeys = {
            anchorFrameType = "PotionAnchorFrameType", anchorFrameFrame = "PotionParentFrame",
            strata = "PotionStrata",
        },
        defaults = { anchorFrameType = "UIPARENT", strata = "MEDIUM" },
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "barsOn")
    yOffset = posOffset

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
            "on the " .. KE:Gold("Cooldowns") .. " tab when " .. KE:Gold("Potions") .. " is ticked there. Only potions that put a buff on the drinker " ..
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
