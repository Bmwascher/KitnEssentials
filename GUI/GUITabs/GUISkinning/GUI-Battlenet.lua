-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Battlenet.lua                                       ║
-- ║  GUI: Battle.net Toast                                   ║
-- ║  Purpose: Configuration panel for the Battlenet module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

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
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        if not checked then
            KE:SkinningReloadPrompt()
        end
        KE:Print("Battle.net Skinning: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

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
