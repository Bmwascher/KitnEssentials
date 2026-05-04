-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonTimersCfg.lua                                ║
-- ║  Purpose: DTimers_General sidebar page — module enable.  ║
-- ║  Future: per-dungeon import / export / preset / reset.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local function GetSettingsDB()
    if not KE.db or not KE.db.profile then return nil end
    return KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
end

-- Module-level preview teardown. Fires whenever the user switches to ANY
-- other sidebar item (contentCleanupCallbacks) or closes the GUI window
-- (onCloseCallbacks). Per-page onCloseCallbacks in Bars/Texts only cover the
-- close path; without this hook, leaving DTimers_Bars for an unrelated module
-- leaves the preview bars stranded on screen.
local function HideAllPreviews()
    if not KitnEssentials then return end
    local mod = KitnEssentials:GetModule("DungeonTimers", true)
    if not mod then return end
    if mod.HideSettingsBarPreviews then mod:HideSettingsBarPreviews() end
    if mod.HideSettingsTextPreviews then mod:HideSettingsTextPreviews() end
end

GUIFrame.contentCleanupCallbacks = GUIFrame.contentCleanupCallbacks or {}
GUIFrame.contentCleanupCallbacks["DungeonTimers"] = HideAllPreviews

GUIFrame.onCloseCallbacks = GUIFrame.onCloseCallbacks or {}
GUIFrame.onCloseCallbacks["DungeonTimers"] = HideAllPreviews

GUIFrame:RegisterContent("DTimers_General", function(scrollChild, yOffset)
    local Theme = KE.Theme
    local db = GetSettingsDB()
    if not db then return yOffset end

    local DT = KitnEssentials and KitnEssentials:GetModule("DungeonTimers", true)

    local function ApplyModuleState(enabled)
        db.Enabled = enabled
        if not DT then return end
        if enabled then
            KitnEssentials:EnableModule("DungeonTimers")
        else
            KitnEssentials:DisableModule("DungeonTimers")
        end
    end

    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Timers", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dungeon Timers", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
            KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
        end,
        msgPopup = true,
        msgText = "Dungeon Timers",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    return yOffset
end)
