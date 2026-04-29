-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Battlenet.lua                                       ║
-- ║  GUI: Battle.net Toast                                   ║
-- ║  Purpose: Configuration panel for the Battlenet module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetBattlenetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBattlenet", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinBattlenet", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Battlenet
    if not db then return yOffset end

    local BNET = GetBattlenetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

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

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Battle.net Toast", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Battle.net Skinning", {
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
        msgText = "Battle.net Skinning",
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
        title = "Position Settings",
        db = db.Position,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "all")
    yOffset = posOffset

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
