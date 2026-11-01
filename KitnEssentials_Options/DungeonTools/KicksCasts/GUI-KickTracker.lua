-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KickTracker.lua                                     ║
-- ║  GUI: Interrupt Tracker                                  ║
-- ║  Purpose: the page host (header and tab strip).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function ApplyModuleState(enabled)
    if not KitnEssentials then return end
    local mod = KitnEssentials:GetModule("KickTracker", true)
    if not mod then return end
    mod.db.Enabled = enabled
    if enabled then
        KitnEssentials:EnableModule("KickTracker")
    else
        KitnEssentials:DisableModule("KickTracker")
    end
end

----------------------------------------------------------------
-- Header: the module card and Show In, above the tab strip
----------------------------------------------------------------
local function BuildHeader(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KickTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset(), true
    end

    local card1 = GUIFrame:CreateCard(scrollChild, "Interrupt Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    -- Forever has no keys.
    local markerSentence = KE.IS_FOREVER
        and "The focus markers teammates announce in the dungeon are read, so their icon can wait on their marked mob.\n\n"
        or "Before a key starts, the focus markers teammates announce are read, so their icon can wait on their marked mob.\n\n"
    card1:AddLabel("Tracks your party's interrupts as cooldown bars, one per teammate with a kick, and " ..
        "as icons on enemy nameplates. By default it runs only in 5-player dungeons; with " ..
        KE:Gold("Only in Dungeons") .. " off it runs in any party outside a raid.\n\n" ..
        "A kick goes on the kicker's bar, and the bar reads " .. KE:ColorTextByTheme("Ready") ..
        " when the tracker's timing says the kick is back. The kicker's icon goes on the nameplate of " ..
        "the mob they stopped; yours goes on your target's nameplate as you cast. " .. markerSentence ..
        "In a dungeon the game often hides who kicked. The Damage Meter then names the kicker when it " ..
        "can. When it cannot, each teammate who could have kicked gets a copy of their bar on cooldown, " ..
        "and the mob a hidden icon of theirs, that the game shows only for the teammate who really kicked.")

    if db.Enabled == false then return card1:GetNextOffset(), true end

    if db.ShowBars == false and db.PlateIcons == false then
        card1:AddNote("Both " .. KE:Gold("Bars") .. " and " .. KE:Gold("Nameplate Icons") ..
            " are off, so the tracker shows nothing.")
    end
    yOffset = card1:GetNextOffset()

    local KT = KitnEssentials and KitnEssentials:GetModule("KickTracker", true)
    local cardShowIn = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    local rowShowIn = GUIFrame:CreateRow(cardShowIn.content, Theme.rowHeightLast)
    rowShowIn:AddWidget(GUIFrame:CreateCheckbox(rowShowIn, "Only in Dungeons", {
        value = db.OnlyInDungeons ~= false,
        tooltip = "On: runs only inside a 5-player dungeon. Off: also runs in any party outside a raid, " ..
            "such as an open-world group or a delve.",
        callback = function(checked)
            db.OnlyInDungeons = checked
            if KT and KT.ApplySettings then KT:ApplySettings() end
        end,
    }), 0.5)
    cardShowIn:AddRow(rowShowIn, Theme.rowHeightLast, 0)
    return cardShowIn:GetNextOffset(), false
end

----------------------------------------------------------------
-- Host: the header above a Bars | Nameplate Icons strip
----------------------------------------------------------------
GUIFrame:RegisterTabbedContent("KickTracker", {
    { id = "KickTrackerBars",   label = "Bars" },
    { id = "KickTrackerPlates", label = "Nameplate Icons" },
}, {
    headerBuilder = BuildHeader,
    defaultTab = function() return "KickTrackerBars" end,
})
