-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BlizzardRaidmanager.lua                             ║
-- ║  GUI: Raid Manager Panel                                 ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           BlizzardRaidmanager module.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetRaidManagerModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardRaidmanager", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinRaidManager", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.RaidManager
    if not db then return yOffset end

    local BRMG = GetRaidManagerModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if BRMG then
            BRMG:ApplySettings()
        end
    end

    local function ApplyModuleState(enabled)
        if not BRMG then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardRaidmanager")
        else
            KitnEssentials:DisableModule("SkinBlizzardRaidmanager")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Raid Manager", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Raid Manager Styling", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            manager:UpdateAll(checked)
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
        msgPopup = true,
        msgText = "Raid Manager Styling",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local ySlider = GUIFrame:CreateSlider(row2, "Y Offset", {
        min = -1100, max = 100, step = 1,
        value = db.Position.YOffset,
        callback = function(val)
            db.Position.YOffset = val
            ApplySettings()
        end,
    })
    row2:AddWidget(ySlider, 1)
    manager:Register(ySlider, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Mouseover Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Mouseover Settings", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local useFade = GUIFrame:CreateCheckbox(row3, "Enable Mouseover", {
        value = db.FadeOnMouseOut ~= false,
        callback = function(checked)
            db.FadeOnMouseOut = checked
            ApplySettings()
        end,
    })
    row3:AddWidget(useFade, 1)
    manager:Register(useFade, "all")
    card3:AddRow(row3, Theme.rowHeight)

    local sepRow = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep3, 1)
    card3:AddRow(sepRow, Theme.rowHeightSeparator)

    local row4 = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local fadeInSlider = GUIFrame:CreateSlider(row4, "Fade In Duration", {
        min = 0, max = 20, step = 0.1,
        value = db.FadeInDuration,
        callback = function(val)
            db.FadeInDuration = val
            ApplySettings()
        end,
    })
    row4:AddWidget(fadeInSlider, 0.5)
    manager:Register(fadeInSlider, "all")

    local fadeOutSlider = GUIFrame:CreateSlider(row4, "Fade Out Duration", {
        min = 0, max = 20, step = 0.1,
        value = db.FadeOutDuration,
        callback = function(val)
            db.FadeOutDuration = val
            ApplySettings()
        end,
    })
    row4:AddWidget(fadeOutSlider, 0.5)
    manager:Register(fadeOutSlider, "all")
    card3:AddRow(row4, Theme.rowHeight)

    local row5 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local alphaSlider = GUIFrame:CreateSlider(row5, "Alpha", {
        min = 0, max = 1, step = 0.1,
        value = db.Alpha,
        callback = function(val)
            db.Alpha = val
            ApplySettings()
        end,
    })
    row5:AddWidget(alphaSlider, 1)
    manager:Register(alphaSlider, "all")
    card3:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
