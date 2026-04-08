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

    ---------------------------------------------------------------------------------
    -- Card 1: Cooldown Manager (/cd, /wa)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cooldown Manager Slash Commands", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local cdmCheck = GUIFrame:CreateCheckbox(row1, "Enable /cd and /wa", db.CDMEnabled ~= false,
        function(checked)
            db.CDMEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "CDM Slash Commands", "On", "Off")
    row1:AddWidget(cdmCheck, 1)
    card1:AddRow(row1, 36)

    card1:AddLabel("|cff888888Registers " .. KE:ColorTextByTheme("/cd") .. " (and " .. KE:ColorTextByTheme("/wa") .. " if WeakAuras is not loaded) to toggle the Blizzard Cooldown Manager settings panel.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Shortcut Commands (/rl, /fs)
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Shortcut Commands", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, 36)
    local rlCheck = GUIFrame:CreateCheckbox(row3, "Enable /rl", db.RLEnabled ~= false,
        function(checked)
            db.RLEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Reload Shortcut", "On", "Off")
    row3:AddWidget(rlCheck, 0.5)

    local fsCheck = GUIFrame:CreateCheckbox(row3, "Enable /fs", db.FSEnabled ~= false,
        function(checked)
            db.FSEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Frame Stack", "On", "Off")
    row3:AddWidget(fsCheck, 0.5)
    card3:AddRow(row3, 36)

    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/rl") .. " reloads the UI.|r")
    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/fs") .. " opens the Frame Stack inspector.|r")

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Party & Instance (/leave, /drop, /reset)
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Party & Instance", yOffset)

    local row4 = GUIFrame:CreateRow(card4.content, 36)
    local leaveCheck = GUIFrame:CreateCheckbox(row4, "Enable /leave + /drop", db.LeavePartyEnabled ~= false,
        function(checked)
            db.LeavePartyEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Leave Party", "On", "Off")
    row4:AddWidget(leaveCheck, 0.5)

    local resetCheck = GUIFrame:CreateCheckbox(row4, "Enable /reset", db.ResetInstancesEnabled ~= false,
        function(checked)
            db.ResetInstancesEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Reset Instances", "On", "Off")
    row4:AddWidget(resetCheck, 0.5)
    card4:AddRow(row4, 36)

    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/leave") .. " or " .. KE:ColorTextByTheme("/drop") .. " leaves your group.|r")
    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/reset") .. " resets all instances (leader only).|r")

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Sound Toggles (/mute, /music)
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Sound Toggles", yOffset)

    local row5 = GUIFrame:CreateRow(card5.content, 36)
    local muteCheck = GUIFrame:CreateCheckbox(row5, "Enable /mute", db.MuteEnabled ~= false,
        function(checked)
            db.MuteEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Mute Sound", "On", "Off")
    row5:AddWidget(muteCheck, 0.5)

    local musicCheck = GUIFrame:CreateCheckbox(row5, "Enable /music", db.MusicEnabled ~= false,
        function(checked)
            db.MusicEnabled = checked
            KE:ApplySlashCommands()
        end,
        true, "Toggle Music", "On", "Off")
    row5:AddWidget(musicCheck, 0.5)
    card5:AddRow(row5, 36)

    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("/mute") .. " toggles all sound on/off.|r")
    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("/music") .. " toggles music on/off.|r")

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: /kitn Commands (info-only)
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "/kitn Subcommands", yOffset)

    card6:AddLabel("|cff888888These commands are always available via " .. KE:ColorTextByTheme("/kitn <command>") .. ":|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn essentials") .. "  |cff888888— Open KitnEssentials settings|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn cd") .. "  |cff888888— Toggle Cooldown Manager panel|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn edit") .. "  |cff888888— Toggle KitnEssentials Edit Mode|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn pi") .. "  |cff888888— Set PI macro target (mouseover or target)|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn clearchat") .. "  |cff888888— Clear all chat frames|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn chatbubbles") .. "  |cff888888— Toggle chat bubbles|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn nameplates") .. "  |cff888888— Toggle |cffFF4444enemy|r|cff888888 nameplates|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn friendplates") .. "  |cff888888— Toggle |cff44FF44friendly|r|cff888888 nameplates|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn actioncam") .. "  |cff888888— Toggle action camera|r")
    card6:AddLabel(KE:ColorTextByTheme("/kitn errors") .. "  |cff888888— Toggle Lua error display|r")

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
