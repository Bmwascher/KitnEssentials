-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RaidControl.lua                                     ║
-- ║  GUI: Raid Control                                       ║
-- ║  Purpose: Configuration panel for the RaidControl        ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("RaidControl", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RaidControl
    if not db then return yOffset end

    local card = GUIFrame:CreateCard(scrollChild, "Raid Control", yOffset)

    card:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("RaidControl")
        else
            KitnEssentials:DisableModule("RaidControl")
            -- Blizzard's own Raid Manager flyout stays hidden until a reload:
            -- the module hides it for the session, it cannot put it back.
            KE:CreateReloadPrompt("Turning off Raid Control hides its button now. A UI reload brings back Blizzard's own Raid Manager tab.")
        end
    end)

    local RC = KitnEssentials:GetModule("RaidControl", true) or {}

    local raidOnly = {}
    if KE.GroupSort then raidOnly[#raidOnly + 1] = "group arrangement" end
    if RC.VANTUS_ADMITTED then raidOnly[#raidOnly + 1] = "a check for who is missing a Vantus Rune" end
    if RC.BUFFS_ADMITTED then
        raidOnly[#raidOnly + 1] = "a strip of raid buff icons that dims the ones nobody brings"
    end
    local raidRows = ""
    if #raidOnly > 0 then
        local n = #raidOnly
        local list = n == 1 and raidOnly[1]
            or table.concat(raidOnly, ", ", 1, n - 1) .. (n > 2 and ", and " or " and ") .. raidOnly[n]
        raidRows = "\n\nIn a raid the panel also offers " .. list .. ". None of that applies in a " ..
            "party, so the panel drops those rows and shrinks."
    end
    raidRows = raidRows .. "\n\nShared Notes and Personal Notes appear in a raid when " ..
        KE:Gold("Northern Sky Raid Tools") .. " is installed."

    local hasDifficulty = not RC.HasDifficultyRow or RC.HasDifficultyRow()

    card:AddLabel("A Raid Control button sits at the top of the screen whenever you are in a group. " ..
        "Click it for a panel with ready check, a 5, 10 or 20 second countdown, " ..
        (hasDifficulty and "the dungeon difficulty, " or "") ..
        "an everyone-assist switch, world markers and a role count. Right-click and " ..
        "drag the button to move it." ..
        "\n\nMarker buttons place world markers; the skull-and-crossbones button clears them all. " ..
        "Hold shift and click any countdown to cancel one that is already running." ..
        raidRows ..
        "\n\nThis replaces the Blizzard Raid Manager tab. Reload the UI after turning it off to get " ..
        "that tab back.")

    return card:GetNextOffset()
end)
