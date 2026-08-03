-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SlashCommands.lua                                   ║
-- ║  GUI: Slash Commands                                     ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           SlashCommands module.                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("SlashCommands", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SlashCommands
    if not db then return yOffset end

    local function Apply()
        if KE.ApplySlashCommands then KE:ApplySlashCommands() end
    end

    ----------------------------------------------------------------
    -- Card 1: Cooldown Manager
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cooldown Manager Slash Commands", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local cdmCheck = GUIFrame:CreateCheckbox(row1, "Enable /cd and /wa", {
        value = db.CDMEnabled ~= false,
        callback = function(checked) db.CDMEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "CDM Slash Commands",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(cdmCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    card1:AddLabel("|cff888888Registers " .. KE:ColorTextByTheme("/cd") .. " (and " .. KE:ColorTextByTheme("/wa") .. " if no aura addon is installed) to toggle the Blizzard Cooldown Manager settings panel.|r")

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Shortcut Commands
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Shortcut Commands", yOffset)

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local rlCheck = GUIFrame:CreateCheckbox(row2, "Enable /rl", {
        value = db.RLEnabled ~= false,
        callback = function(checked) db.RLEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Reload Shortcut",
        msgOn = "On",
        msgOff = "Off",
    })
    row2:AddWidget(rlCheck, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    card2:AddLabel("|cff888888" .. KE:ColorTextByTheme("/rl") .. " reloads the UI.|r")

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: /kitn Subcommands (info-only)
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "/kitn Subcommands", yOffset)

    card3:AddLabel("|cff888888These commands are always available via " .. KE:ColorTextByTheme("/kitn <command>") .. ":|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn essentials") .. "  |cff888888— Open KitnEssentials settings|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn cd") .. "  |cff888888— Toggle Cooldown Manager panel|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn edit") .. "  |cff888888— Toggle KitnEssentials Edit Mode|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn pi") .. "  |cff888888— Set PI macro target (mouseover or target)|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn clearchat") .. "  |cff888888— Clear all chat frames|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn chatbubbles") .. "  |cff888888— Toggle chat bubbles|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn nameplates") .. "  |cff888888— Toggle |cffFF4444enemy|r|cff888888 nameplates|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn friendplates") .. "  |cff888888— Toggle |cff44FF44friendly|r|cff888888 nameplates|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn actioncam") .. "  |cff888888— Toggle action camera|r")
    card3:AddLabel(KE:ColorTextByTheme("/kitn errors") .. "  |cff888888— Toggle Lua error display|r")

    yOffset = card3:GetNextOffset()

    return yOffset
end)
