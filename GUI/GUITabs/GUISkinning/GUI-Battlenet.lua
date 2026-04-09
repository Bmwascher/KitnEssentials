-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Battlenet.lua                                       ║
-- ║  GUI: Battle.net Toast                                   ║
-- ║  Purpose: Configuration panel for the Battlenet module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Local references
local table_insert = table.insert
local ipairs = ipairs

-- Helper to get module
local function GetBattlenetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBattlenet", true)
    end
    return nil
end

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("SkinBattlenet", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Battlenet
    if not db then return yOffset end

    local BNET = GetBattlenetModule()
    local allWidgets = {}

    local function ApplySettings()
        if BNET then
            BNET:ApplySettings()
        end
    end

    local function ApplyModuleState(enabled)
        if not BNET then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBattlenet")
        else
            KitnEssentials:DisableModule("SkinBattlenet")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Battle.net Toast", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Battle.net Skinning", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
        true, "Battle.net Skinning", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Position Settings
    ---------------------------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db.Position,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        onChangeCallback = function()
            ApplySettings()
        end,
    })
    table_insert(allWidgets, posCard)
    yOffset = posOffset

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
