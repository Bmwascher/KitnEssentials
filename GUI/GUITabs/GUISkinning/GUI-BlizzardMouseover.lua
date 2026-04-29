-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardMouseover.lua                               ║
-- ║  GUI: Blizzard Mouseover                                 ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           BlizzardMouseover module.                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetBlizzardMouseoverModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMouseover", true)
    end
    return nil
end

local function GetActionBarsModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinActionBars", true)
    end
    return nil
end

local function GetMicroMenuModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMicroMenu", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinMouseover", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Mouseover
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local BMO = GetBlizzardMouseoverModule()
    local abDB = KE.db and KE.db.profile.Skinning.ActionBars
    local mmDB = KE.db and KE.db.profile.Skinning.MicroMenu

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if BMO then BMO:ApplySettings() end
    end

    local function ApplyMouseoverState(enabled)
        if not BMO then return end
        BMO.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardMouseover")
        else
            KitnEssentials:DisableModule("SkinBlizzardMouseover")
        end
    end

    manager:SetCondition("bag", function()
        return db.BagMouseover and db.BagMouseover.Enabled ~= false
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + About
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Blizzard Mouseover", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Blizzard Mouseover", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyMouseoverState(checked)
            if not checked then
                KE:SkinningReloadPrompt()
            end
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Blizzard Mouseover",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local sepRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sepWidget = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sepWidget, 1)
    card1:AddRow(sepRow, Theme.rowHeightSeparator)

    local descRowSize = 30
    local rowDesc = GUIFrame:CreateRow(card1.content, descRowSize)
    local descText = GUIFrame:CreateText(rowDesc,
        KE:ColorTextByTheme("About"),
        "Fades supported Blizzard UI elements until you mouseover them.",
        descRowSize, "hide")
    rowDesc:AddWidget(descText, 1)
    manager:Register(descText, "all")
    card1:AddRow(rowDesc, descRowSize, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Bag Bar (owned by this module — full settings here)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Bag Bar", yOffset)
    manager:Register(card2, "all")

    local rowBagEnable = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local bagEnableCheck = GUIFrame:CreateCheckbox(rowBagEnable, "Enable BagBar Mouseover", {
        value = db.BagMouseover.Enabled ~= false,
        callback = function(checked)
            db.BagMouseover.Enabled = checked
            if BMO then
                BMO:ToggleElement("bags", checked)
                ApplySettings()
            end
            RefreshStates()
        end,
    })
    rowBagEnable:AddWidget(bagEnableCheck, 1)
    manager:Register(bagEnableCheck, "all")
    card2:AddRow(rowBagEnable, Theme.rowHeight)

    local rowAlpha = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local nonMouseoverAlpha = GUIFrame:CreateSlider(rowAlpha, "Alpha When No Mouseover", {
        min = 0, max = 1, step = 0.1,
        value = db.Alpha,
        callback = function(val)
            db.Alpha = val
            ApplySettings()
        end,
    })
    rowAlpha:AddWidget(nonMouseoverAlpha, 1)
    manager:Register(nonMouseoverAlpha, "bag")
    card2:AddRow(rowAlpha, Theme.rowHeight)

    local rowFade = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local fadeInSlider = GUIFrame:CreateSlider(rowFade, "Fade In Duration", {
        min = 0, max = 10, step = 0.1,
        value = db.FadeInDuration,
        callback = function(val)
            db.FadeInDuration = val
        end,
    })
    rowFade:AddWidget(fadeInSlider, 0.5)
    manager:Register(fadeInSlider, "bag")

    local fadeOutSlider = GUIFrame:CreateSlider(rowFade, "Fade Out Duration", {
        min = 0, max = 10, step = 0.1,
        value = db.FadeOutDuration,
        callback = function(val)
            db.FadeOutDuration = val
        end,
    })
    rowFade:AddWidget(fadeOutSlider, 0.5)
    manager:Register(fadeOutSlider, "bag")
    card2:AddRow(rowFade, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Other Elements (cross-module toggles)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Other Elements", yOffset)
    manager:Register(card3, "all")

    local infoRowSize = 30
    local rowInfo = GUIFrame:CreateRow(card3.content, infoRowSize)
    local infoText = GUIFrame:CreateText(rowInfo,
        KE:ColorTextByTheme("Quick Toggles"),
        KE:ColorTextByTheme("• ") .. "These elements have their own mouseover settings in their respective pages.",
        infoRowSize, "hide")
    rowInfo:AddWidget(infoText, 1)
    manager:Register(infoText, "all")
    card3:AddRow(rowInfo, infoRowSize)

    local rowSep2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    card3:AddRow(rowSep2, Theme.rowHeightSeparator)

    local hasAB = abDB ~= nil
    local hasMM = mmDB ~= nil

    if hasAB then
        local rowAB = GUIFrame:CreateRow(card3.content, hasMM and Theme.rowHeight or Theme.rowHeightLast)
        local abMouseoverEnabled = abDB.Mouseover and abDB.Mouseover.Enabled ~= false
        local abCheck = GUIFrame:CreateCheckbox(rowAB, "Action Bars Mouseover", {
            value = abMouseoverEnabled,
            callback = function(checked)
                if abDB.Mouseover then
                    abDB.Mouseover.Enabled = checked
                end
                local abModule = GetActionBarsModule()
                if abModule and abModule.UpdateSettings then
                    abModule:UpdateSettings("mouseover")
                end
            end,
        })
        rowAB:AddWidget(abCheck, 1)
        manager:Register(abCheck, "all")
        if hasMM then
            card3:AddRow(rowAB, Theme.rowHeight)
        else
            card3:AddRow(rowAB, Theme.rowHeightLast, 0)
        end
    end

    if hasMM then
        local rowMM = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        local mmMouseoverEnabled = mmDB.Mouseover and mmDB.Mouseover.Enabled ~= false
        local mmCheck = GUIFrame:CreateCheckbox(rowMM, "Micro Menu Mouseover", {
            value = mmMouseoverEnabled,
            callback = function(checked)
                if mmDB.Mouseover then
                    mmDB.Mouseover.Enabled = checked
                end
                local mmModule = GetMicroMenuModule()
                if mmModule and mmModule.UpdateAlpha then
                    mmModule:UpdateAlpha()
                end
            end,
        })
        rowMM:AddWidget(mmCheck, 1)
        manager:Register(mmCheck, "all")
        card3:AddRow(rowMM, Theme.rowHeightLast, 0)
    end

    yOffset = card3:GetNextOffset()

    RefreshStates()
    return yOffset
end)
