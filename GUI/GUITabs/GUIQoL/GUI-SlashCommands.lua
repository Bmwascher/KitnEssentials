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

    card1:AddLabel("|cff888888Registers " .. KE:ColorTextByTheme("/cd") .. " (and " .. KE:ColorTextByTheme("/wa") .. " if WeakAuras is not loaded) to toggle the Blizzard Cooldown Manager settings panel.|r")

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
    row2:AddWidget(rlCheck, 0.5)

    local fsCheck = GUIFrame:CreateCheckbox(row2, "Enable /fs", {
        value = db.FSEnabled ~= false,
        callback = function(checked) db.FSEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Frame Stack",
        msgOn = "On",
        msgOff = "Off",
    })
    row2:AddWidget(fsCheck, 0.5)
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    card2:AddLabel("|cff888888" .. KE:ColorTextByTheme("/rl") .. " reloads the UI.|r")
    card2:AddLabel("|cff888888" .. KE:ColorTextByTheme("/fs") .. " opens the Frame Stack inspector.|r")

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Party & Instance
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Party & Instance", yOffset)

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local leaveCheck = GUIFrame:CreateCheckbox(row3, "Enable /leave + /drop", {
        value = db.LeavePartyEnabled ~= false,
        callback = function(checked) db.LeavePartyEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Leave Party",
        msgOn = "On",
        msgOff = "Off",
    })
    row3:AddWidget(leaveCheck, 0.5)

    local resetCheck = GUIFrame:CreateCheckbox(row3, "Enable /reset", {
        value = db.ResetInstancesEnabled ~= false,
        callback = function(checked) db.ResetInstancesEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Reset Instances",
        msgOn = "On",
        msgOff = "Off",
    })
    row3:AddWidget(resetCheck, 0.5)
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/leave") .. " or " .. KE:ColorTextByTheme("/drop") .. " leaves your group.|r")
    card3:AddLabel("|cff888888" .. KE:ColorTextByTheme("/reset") .. " resets all instances (leader only).|r")

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Sound Toggles
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Sound Toggles", yOffset)

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local muteCheck = GUIFrame:CreateCheckbox(row4, "Enable /mute", {
        value = db.MuteEnabled ~= false,
        callback = function(checked) db.MuteEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Mute Sound",
        msgOn = "On",
        msgOff = "Off",
    })
    row4:AddWidget(muteCheck, 0.5)

    local musicCheck = GUIFrame:CreateCheckbox(row4, "Enable /music", {
        value = db.MusicEnabled ~= false,
        callback = function(checked) db.MusicEnabled = checked; Apply() end,
        msgPopup = true,
        msgText = "Toggle Music",
        msgOn = "On",
        msgOff = "Off",
    })
    row4:AddWidget(musicCheck, 0.5)
    card4:AddRow(row4, Theme.rowHeightLast, 0)

    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/mute") .. " toggles all sound on/off.|r")
    card4:AddLabel("|cff888888" .. KE:ColorTextByTheme("/music") .. " toggles music on/off.|r")

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: /kitn Subcommands (info-only)
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "/kitn Subcommands", yOffset)

    card5:AddLabel("|cff888888These commands are always available via " .. KE:ColorTextByTheme("/kitn <command>") .. ":|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn essentials") .. "  |cff888888— Open KitnEssentials settings|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn cd") .. "  |cff888888— Toggle Cooldown Manager panel|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn edit") .. "  |cff888888— Toggle KitnEssentials Edit Mode|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn pi") .. "  |cff888888— Set PI macro target (mouseover or target)|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn clearchat") .. "  |cff888888— Clear all chat frames|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn chatbubbles") .. "  |cff888888— Toggle chat bubbles|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn nameplates") .. "  |cff888888— Toggle |cffFF4444enemy|r|cff888888 nameplates|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn friendplates") .. "  |cff888888— Toggle |cff44FF44friendly|r|cff888888 nameplates|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn actioncam") .. "  |cff888888— Toggle action camera|r")
    card5:AddLabel(KE:ColorTextByTheme("/kitn errors") .. "  |cff888888— Toggle Lua error display|r")

    yOffset = card5:GetNextOffset()

    return yOffset
end)
