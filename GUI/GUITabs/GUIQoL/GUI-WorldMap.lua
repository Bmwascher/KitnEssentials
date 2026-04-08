-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WorldMap.lua                                        ║
-- ║  GUI: World Map Scaler                                   ║
-- ║  Purpose: Configuration panel for the WorldMap module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WorldMap", true)
    end
    return nil
end

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------
GUIFrame:RegisterContent("WorldMap", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.WorldMap
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local WM = GetModule()

    local function ApplySettings()
        if WM then
            WM:UpdateDB()
            WM:ApplySettings()
        end
    end

    -- ----------------------------------------------------------------
    -- Card 1: Map Scale
    -- ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Map Scale", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 40)
    local scaleCheck = GUIFrame:CreateCheckbox(row1a, "Increase World Map Scale",
        db.ScaleEnabled == true,
        function(checked)
            db.ScaleEnabled = checked
            ApplySettings()
        end)
    row1a:AddWidget(scaleCheck, 0.5)

    local scaleSlider = GUIFrame:CreateSlider(row1a, "Scale", 1.0, 2.0, 0.05,
        db.Scale or 1.2, 100,
        function(val)
            db.Scale = val
            if WM then
                WM.scaleApplied = false
            end
            ApplySettings()
        end)
    row1a:AddWidget(scaleSlider, 0.5)
    card1:AddRow(row1a, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    -- ----------------------------------------------------------------
    -- Card 2: Waypoint Search Bar
    -- ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Waypoint Search", yOffset)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local waypointCheck = GUIFrame:CreateCheckbox(row2a, "Coordinate Search Bar on World Map",
        db.WaypointBarEnabled == true,
        function(checked)
            db.WaypointBarEnabled = checked
            ApplySettings()
        end)
    row2a:AddWidget(waypointCheck, 1)
    card2:AddRow(row2a, 40)

    card2:AddLabel("|cff888888Type coordinates (e.g. 45.2 67.8) and press Enter to set a waypoint.|r")

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    return yOffset
end)
