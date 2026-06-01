-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelOnCursor.lua                                  ║
-- ║  GUI: Healer Utilities > Dispel on Cursor                ║
-- ║  Purpose: Cross-link page for the Dispel Countdown       ║
-- ║  settings housed under Combat Utilities > Cursor Effects.║
-- ║  Renders the same shared card; writes to the same DB     ║
-- ║  keys — no duplication of runtime behavior.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local function GetModule()
    if not KitnEssentials then return nil end
    return KitnEssentials:GetModule("Cursor", true)
end

GUIFrame:RegisterContent("DispelOnCursor", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Cursor
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function RefreshModule()
        local M = GetModule()
        if M and M.ApplyDispelSatellite then M:ApplyDispelSatellite() end
    end

    local function RefreshStates()
        manager:UpdateAll(true)
    end

    -- Note card: orient the user to where the settings live canonically.
    local noteCard = GUIFrame:CreateCard(scrollChild, "Dispel on Cursor", yOffset)
    local noteRow = GUIFrame:CreateRow(noteCard.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        "Shows a dispel-spell cooldown countdown next to your cursor. " ..
        "These are the same settings as Combat Utilities > Cursor Effects > Dispel Countdown.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    noteCard:AddRow(noteRow, 50, 0)
    yOffset = noteCard:GetNextOffset()

    yOffset = GUIFrame:CreateDispelCursorCard(scrollChild, yOffset, {
        db            = db,
        manager       = manager,
        refresh       = RefreshModule,
        refreshStates = RefreshStates,
        getModule     = GetModule,
    })

    manager:UpdateAll(true)
    return yOffset
end)
