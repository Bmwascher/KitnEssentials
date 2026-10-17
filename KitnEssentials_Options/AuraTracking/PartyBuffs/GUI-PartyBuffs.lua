-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyBuffs.lua                                      ║
-- ║  GUI: Party Cooldowns                                    ║
-- ║  Purpose: the page host (header and tab strip) and the   ║
-- ║           two placeholder tabs.                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local DESCRIPTION = "Shows the cooldowns that matter for your group beside each party member's frame: " ..
    "their spec's offensive and personal defensive spells and their on-use trinkets. An icon is full color " ..
    "when ready, shows the buff's timer while it is up, then turns gray with the time left." ..
    "\n\nA party member's spec comes from |cffffd100LibSpecialization|r or a quiet automatic inspect; until " ..
    "it is known, that member shows no cooldown icons. Externals and potions your party members receive still " ..
    "show while active, after the cooldown icons." ..
    "\n\nWorks on Blizzard's party frames and on |cffffd100EllesmereUI|r frames. Not shown in raids."

local function Placeholder(id, title, note)
    GUIFrame:RegisterContent(id, function(scrollChild, yOffset)
        local card = GUIFrame:CreateCard(scrollChild, title, yOffset)
        card:AddNote(note)
        return card:GetNextOffset()
    end)
end

Placeholder("PartyBuffsPotions", "Party Potions",
    "Party potion cooldowns arrive in a later update. Potions your party uses still show while active, from the Cooldowns tab.")
Placeholder("PartyBuffsHealerExternals", "Healer Externals",
    "A timer on your healer's external cooldowns arrives in a later update.")

GUIFrame:RegisterTabbedContent("PartyBuffs", {
    { id = "PartyBuffsCooldowns",       label = "Cooldowns" },
    { id = "PartyBuffsPotions",         label = "Potions" },
    { id = "PartyBuffsHealerExternals", label = "Healer Externals" },
}, {
    headerBuilder = function(scrollChild, yOffset)
        local db = KE.db and KE.db.profile.PartyBuffs
        if not db then
            local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
            errorCard:AddLabel("Database not available")
            return errorCard:GetNextOffset(), true
        end
        local card = GUIFrame:CreateCard(scrollChild, "Party Cooldowns", yOffset)
        card:AddHeaderToggle(db.Enabled == true, function(checked)
            if not KitnEssentials then return end
            db.Enabled = checked
            if checked then
                KitnEssentials:EnableModule("PartyBuffs")
            else
                KitnEssentials:DisableModule("PartyBuffs")
            end
        end)
        -- Lone header bar: a disabled module shows its switch and nothing else.
        if db.Enabled ~= true then return card:GetNextOffset(), true end
        card:AddLabel(DESCRIPTION)
        return card:GetNextOffset(), false
    end,
})
