-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-VehicleExit.lua                                     ║
-- ║  GUI: Vehicle Exit Button                                ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           VehicleExit module.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("VehicleExit", true)
    end
    return nil
end

GUIFrame:RegisterContent("VehicleExit", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.VehicleExit
    if not db then return yOffset end

    local VE = GetModule()

    local function ApplyPosition()
        if VE and VE.Refresh then VE:Refresh() end
    end

    local function ApplyState(enabled)
        if not VE then return end
        VE.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("VehicleExit")
        else KitnEssentials:DisableModule("VehicleExit") end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Vehicle Exit Button", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplyState(checked)
        KE:Print("Vehicle Exit Button: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
        GUIFrame:RefreshContent()
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightNote)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Takes over where the vehicle exit button sits. Blizzard's Edit Mode " ..
        "and some action bar addons both move this button, which is why it can jump back after a " ..
        "reload. Applied a few seconds after you log in.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeightNote, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    -- Anchor To Frame is offered here where most pages hide it: this button's
    -- whole problem is that it belongs beside something else -- an action bar,
    -- a cast bar -- and anchoring to that frame is what keeps it there.
    local _, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplyPosition,
    })
    yOffset = posOffset

    return yOffset
end)
