-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardMicroMenu.lua                               ║
-- ║  GUI: Micro Menu                                         ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           BlizzardMicroMenu module.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetMicroMenuModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMicroMenu", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinMicroMenu", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.MicroMenu
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local MM = GetMicroMenuModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if MM then MM:UpdateMicroBar() end
    end

    local function UpdateAlphaState()
        if MM then MM:UpdateAlpha() end
    end

    local function ApplyMicroMenuState(enabled)
        if not MM then return end
        MM.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardMicroMenu")
        else
            KitnEssentials:DisableModule("SkinBlizzardMicroMenu")
        end
    end

    manager:SetCondition("bg", function() return db.ShowBackdrop ~= false end)
    manager:SetCondition("mouseover", function()
        return db.Mouseover and db.Mouseover.Enabled ~= false
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Micro Menu Skinning", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Micro Menu Skinning", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyMicroMenuState(checked)
            RefreshStates()
            KE:CreateReloadPrompt("Enabling/Disabling this UI element requires a reload to take full effect.")
        end,
        msgPopup = true,
        msgText = "Micro Menu Skinning",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
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
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Mouseover Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Mouseover Settings", yOffset)
    manager:Register(card3, "all")

    local mouseOverDB = db.Mouseover

    local rowMO1 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local mouseOverEnableCheck = GUIFrame:CreateCheckbox(rowMO1, "Enable Micro Menu Mouseover", {
        value = mouseOverDB.Enabled ~= false,
        callback = function(checked)
            mouseOverDB.Enabled = checked
            UpdateAlphaState()
            RefreshStates()
        end,
    })
    rowMO1:AddWidget(mouseOverEnableCheck, 0.5)
    manager:Register(mouseOverEnableCheck, "all")

    local nonMouseoverAlpha = GUIFrame:CreateSlider(rowMO1, "Alpha When No Mouseover", {
        min = 0, max = 1, step = 0.1,
        value = mouseOverDB.Alpha,
        callback = function(val)
            mouseOverDB.Alpha = val
            ApplySettings()
        end,
    })
    rowMO1:AddWidget(nonMouseoverAlpha, 0.5)
    manager:Register(nonMouseoverAlpha, "mouseover")
    card3:AddRow(rowMO1, Theme.rowHeight)

    local rowMO2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local fadeInSlider = GUIFrame:CreateSlider(rowMO2, "Fade In Duration", {
        min = 0, max = 10, step = 0.1,
        value = mouseOverDB.FadeInDuration,
        callback = function(val)
            mouseOverDB.FadeInDuration = val
        end,
    })
    rowMO2:AddWidget(fadeInSlider, 0.5)
    manager:Register(fadeInSlider, "mouseover")

    local fadeOutSlider = GUIFrame:CreateSlider(rowMO2, "Fade Out Duration", {
        min = 0, max = 10, step = 0.1,
        value = mouseOverDB.FadeOutDuration,
        callback = function(val)
            mouseOverDB.FadeOutDuration = val
        end,
    })
    rowMO2:AddWidget(fadeOutSlider, 0.5)
    manager:Register(fadeOutSlider, "mouseover")
    card3:AddRow(rowMO2, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Button Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Button Settings", yOffset)
    manager:Register(card4, "all")

    local rowBtn1 = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local buttonWidthSlider = GUIFrame:CreateSlider(rowBtn1, "Button Width", {
        min = 5, max = 50, step = 1,
        value = db.ButtonWidth,
        callback = function(val)
            db.ButtonWidth = val
            ApplySettings()
        end,
    })
    rowBtn1:AddWidget(buttonWidthSlider, 0.5)
    manager:Register(buttonWidthSlider, "all")

    local buttonHeightSlider = GUIFrame:CreateSlider(rowBtn1, "Button Height", {
        min = 5, max = 50, step = 1,
        value = db.ButtonHeight,
        callback = function(val)
            db.ButtonHeight = val
            ApplySettings()
        end,
    })
    rowBtn1:AddWidget(buttonHeightSlider, 0.5)
    manager:Register(buttonHeightSlider, "all")
    card4:AddRow(rowBtn1, Theme.rowHeight)

    local rowBtn2 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local buttonSpacingSlider = GUIFrame:CreateSlider(rowBtn2, "Button Spacing", {
        min = -20, max = 20, step = 1,
        value = db.ButtonSpacing,
        callback = function(val)
            db.ButtonSpacing = val
            ApplySettings()
        end,
    })
    rowBtn2:AddWidget(buttonSpacingSlider, 1)
    manager:Register(buttonSpacingSlider, "all")
    card4:AddRow(rowBtn2, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Backdrop Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop Settings", yOffset)
    manager:Register(card5, "all")

    local rowBg1 = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local backdropCheck = GUIFrame:CreateCheckbox(rowBg1, "Enable Backdrop", {
        value = db.ShowBackdrop ~= false,
        callback = function(checked)
            db.ShowBackdrop = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    rowBg1:AddWidget(backdropCheck, 1)
    manager:Register(backdropCheck, "all")
    card5:AddRow(rowBg1, Theme.rowHeight)

    local rowBg2 = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local backdropColor = GUIFrame:CreateColorPicker(rowBg2, "Backdrop Color", {
        color = db.BackdropColor,
        callback = function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowBg2:AddWidget(backdropColor, 1)
    manager:Register(backdropColor, "bg")
    card5:AddRow(rowBg2, Theme.rowHeight)

    local rowBg3 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local borderColor = GUIFrame:CreateColorPicker(rowBg3, "Backdrop Border Color", {
        color = db.BackdropBorderColor,
        callback = function(r, g, b, a)
            db.BackdropBorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowBg3:AddWidget(borderColor, 1)
    manager:Register(borderColor, "bg")
    card5:AddRow(rowBg3, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
