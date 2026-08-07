-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PotionReady.lua                                     ║
-- ║  GUI: Combat Potion Ready                                ║
-- ║  Purpose: Configuration panel for the PotionReady module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PotionReady", true)
    end
    return nil
end

GUIFrame:RegisterContent("PotionReady", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PotionReady
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
        if mod and mod.CheckPotions then mod:CheckPotions() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PotionReady")
        else
            KitnEssentials:DisableModule("PotionReady")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Potion Ready", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Combat Potion Ready: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Display & Visibility
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display & Visibility", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local textBox = GUIFrame:CreateEditBox(row2a, "Display Text", {
        value = db.Text or "Potion Ready",
        callback = function(text) db.Text = text; ApplySettings() end,
    })
    row2a:AddWidget(textBox, 1)
    manager:Register(textBox, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local instanceCheck = GUIFrame:CreateCheckbox(row2b, "Instances Only", {
        value = db.InstanceOnly ~= false,
        callback = function(checked) db.InstanceOnly = checked; ApplySettings() end,
    })
    row2b:AddWidget(instanceCheck, 1/3)
    manager:Register(instanceCheck, "all")

    local combatCheck = GUIFrame:CreateCheckbox(row2b, "In Combat Only", {
        value = db.CombatOnly,
        callback = function(checked) db.CombatOnly = checked; ApplySettings() end,
    })
    row2b:AddWidget(combatCheck, 1/3)
    manager:Register(combatCheck, "all")

    local healerCheck = GUIFrame:CreateCheckbox(row2b, "Hide for Healers", {
        value = db.DisableOnHealer,
        callback = function(checked) db.DisableOnHealer = checked; ApplySettings() end,
    })
    row2b:AddWidget(healerCheck, 1/3)
    manager:Register(healerCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

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
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "all",
        isLast     = true,
        colorMode  = { key = "ColorMode", onChange = RefreshStates },
        colors     = {
            { label = "Custom Color", key = "Color", default = { 0, 1, 0, 1 }, group = "customColor" },
        },
    })

    RefreshStates()
    return yOffset
end)
