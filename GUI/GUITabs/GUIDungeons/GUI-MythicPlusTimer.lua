-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MythicPlusTimer.lua                                 ║
-- ║  GUI: Mythic+ Timer                                      ║
-- ║  Purpose: Configuration panel for the MythicPlusTimer    ║
-- ║           module. Phase 0 stub — Enable card only;       ║
-- ║           tabbed pages (Timer/Forces/Objectives/Deaths/  ║
-- ║           Enemy Overlay/General) land in the GUI phase.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetMPTModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("MythicPlusTimer", true)
    end
    return nil
end

GUIFrame:RegisterContent("MythicPlusTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MythicPlusTimer
    if not db then return yOffset end

    local MPT = GetMPTModule()

    local function ApplyModuleState(enabled)
        if not MPT then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("MythicPlusTimer")
        else
            KitnEssentials:DisableModule("MythicPlusTimer")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Mythic+ Timer", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Mythic+ Timer", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
        end,
        msgPopup = true,
        msgText = "Mythic+ Timer",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    return card1:GetNextOffset()
end)
