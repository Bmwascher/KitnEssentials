---@class KE
local KE = select(2, ...)
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
        KE:Print("Raid Control: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return card:GetNextOffset() end

    card:AddNote("A Raid Control button sits at the top of the screen whenever you are in a group. Click it for a panel with ready check, a 5, 10 or 20 second countdown, the dungeon difficulty, an everyone-assist switch, world markers and a role count.")
    card:AddNote("Marker buttons place world markers; the skull-and-crossbones button clears them all. Hold shift and click any countdown to cancel one that is already running.")
    card:AddNote("In a raid the panel also offers group arrangement, a check for who is missing a Vantus Rune, and a strip of raid buff icons that dims the ones nobody brings. None of that applies in a party, so the panel drops those rows and shrinks.")
    card:AddNote("Shared Notes and Personal Notes appear when Northern Sky Raid Tools is installed.")
    card:AddNote("This replaces the Blizzard Raid Manager tab. Reload the UI after turning it off to get that tab back.")

    return card:GetNextOffset()
end)
