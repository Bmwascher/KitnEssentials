-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PartyBuffs.lua                                      ║
-- ║  GUI: Party Cooldowns                                    ║
-- ║  Purpose: the page host (header and tab strip).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

local DESCRIPTION = "Shows the cooldowns that matter to your group beside each party member's frame: " ..
    "their spec's offensive and personal defensive spells, plus their on-use trinkets. An icon is full color " ..
    "when ready, shows the buff's timer while it is up, then turns gray with the time left." ..
    "\n\nA member's spec comes from " .. KE:Gold("LibSpecialization") .. " or a quiet automatic inspect. " ..
    "Until it is known, that member shows no cooldown icons. Externals and potions your party members " ..
    "receive still show while active, after the cooldown icons." ..
    "\n\nThe " .. KE:Gold("General") .. " tab holds " .. KE:Gold("Show In") .. ", the font and the colors, " ..
    "which the party frame icons, Potion bars and Raid Cooldowns share. The " .. KE:Gold("Potions") ..
    " tab shows each member's potion cooldown as a bar. The " .. KE:Gold("Raid Cooldowns") ..
    " tab shows your party's externals and raid cooldowns in a box you can move." ..
    "\n\nWorks on Blizzard's party frames and " .. KE:Gold("EllesmereUI") .. " frames. Not shown in raids."

GUIFrame:RegisterTabbedContent("PartyBuffs", {
    { id = "PartyBuffsGeneral",         label = "General" },
    { id = "PartyBuffsCooldowns",       label = "Cooldowns" },
    { id = "PartyBuffsPotions",         label = "Potions" },
    { id = "PartyBuffsHealerExternals", label = "Raid Cooldowns" },
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
        card:AddLabel(DESCRIPTION)
        if db.Enabled ~= true then return card:GetNextOffset(), true end
        return card:GetNextOffset(), false
    end,
})
