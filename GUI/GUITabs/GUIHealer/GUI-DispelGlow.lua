-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelGlow.lua                                      ║
-- ║  GUI: Dispel Glow (Enable + Note; ElvUI-gated)           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("DispelGlow", true)
end

GUIFrame:RegisterContent("DispelGlow", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DispelGlow
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local hasElv = _G.ElvUI ~= nil

    ----------------------------------------------------------------
    -- Card 1: Enable + Note
    -- (Pure frame overlay — no position/EditMode/preview.)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dispel Glow", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dispel Glow", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            local mod = GetModule()
            if mod then
                if checked then KitnEssentials:EnableModule("DispelGlow")
                else KitnEssentials:DisableModule("DispelGlow") end
            end
        end,
        msgPopup = true,
        msgText  = "Dispel Glow",
        msgOn    = "On",
        msgOff   = "Off",
    })
    -- No ElvUI → the module can't start; gray the toggle so it reads as
    -- unavailable rather than broken.
    if not hasElv and enableCheck.SetEnabled then enableCheck:SetEnabled(false) end
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteHeight = 90
    local noteBody = hasElv
        and (KE:ColorTextByTheme("-") .. " Highlights ElvUI party/raid/tank frames when a dispellable " ..
             "debuff is present, including private auras (dungeon-mechanic debuffs the normal aura " ..
             "API can't see).\n" ..
             KE:ColorTextByTheme("-") .. " Uses Blizzard's native dispel overlay anchored to each frame.\n" ..
             KE:ColorTextByTheme("-") .. " Border color follows your Aura Debuffs dispel-type palette.")
        or  (KE:ColorTextByTheme("-") .. " Dispel Glow requires ElvUI. Install/enable ElvUI to use this feature.")

    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        noteBody,
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)

    yOffset = card1:GetNextOffset()

    return yOffset
end)
