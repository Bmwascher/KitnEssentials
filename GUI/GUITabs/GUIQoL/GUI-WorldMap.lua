-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WorldMap.lua                                        ║
-- ║  GUI: World Map Scaler                                   ║
-- ║  Purpose: Configuration panel for the WorldMap module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WorldMap", true)
    end
    return nil
end

GUIFrame:RegisterContent("WorldMap", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.WorldMap
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local WM = GetModule()

    local function ApplySettings()
        if WM then
            WM:UpdateDB()
            WM:ApplySettings()
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Map Scale
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Map Scale", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local scaleCheck = GUIFrame:CreateCheckbox(row1, "Increase World Map Scale", {
        value = db.ScaleEnabled == true,
        callback = function(checked) db.ScaleEnabled = checked; ApplySettings() end,
    })
    row1:AddWidget(scaleCheck, 0.5)

    local scaleSlider = GUIFrame:CreateSlider(row1, "Scale", {
        min = 1.0, max = 2.0, step = 0.05,
        value = db.Scale or 1.2,
        callback = function(val)
            db.Scale = val
            if WM then WM.scaleApplied = false end
            ApplySettings()
        end,
    })
    row1:AddWidget(scaleSlider, 0.5)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Waypoint Search
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Waypoint Search", yOffset)

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local waypointCheck = GUIFrame:CreateCheckbox(row2, "Coordinate Search Bar on World Map", {
        value = db.WaypointBarEnabled == true,
        callback = function(checked) db.WaypointBarEnabled = checked; ApplySettings() end,
    })
    row2:AddWidget(waypointCheck, 1)
    card2:AddRow(row2, Theme.rowHeightLast)

    local row2note = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local note2 = GUIFrame:CreateText(row2note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Type coordinates (e.g. 45.2 67.8) and press Enter to set a waypoint.",
        Theme.rowHeight, "hide")
    row2note:AddWidget(note2, 1)
    card2:AddRow(row2note, Theme.rowHeight, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: City Map Icons
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "City Map Icons", yOffset)

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconsCheck = GUIFrame:CreateCheckbox(row3a, "Enable City Map Icons", {
        value = db.MapIconsEnabled == true,
        callback = function(checked) db.MapIconsEnabled = checked; ApplySettings() end,
    })
    row3a:AddWidget(iconsCheck, 1)
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local profCheck = GUIFrame:CreateCheckbox(row3b, "Only Show Trainers for Learned Professions", {
        value = db.MapIconsProfessionFilter == true,
        callback = function(checked) db.MapIconsProfessionFilter = checked; ApplySettings() end,
    })
    row3b:AddWidget(profCheck, 1)
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local styleDropdown = GUIFrame:CreateDropdown(row3c, "Icon Style", {
        options = { regular = "Regular (Item Icons)", small = "Small (Minimap Style + Glow)" },
        value = db.MapIconsStyle or "regular",
        callback = function(value)
            db.MapIconsStyle = value
            if WM then
                WM:UpdateDB()
                WM:RebuildMapIcons()
            end
        end,
    })
    row3c:AddWidget(styleDropdown, 1)
    card3:AddRow(row3c, Theme.rowHeightLast)

    local row3note = GUIFrame:CreateRow(card3.content, 50)
    local note3 = GUIFrame:CreateText(row3note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Adds service, vendor, and trainer pins to the Silvermoon, Stormwind, and Orgrimmar city maps.\n" ..
        KE:ColorTextByTheme("-") .. " Click a pin to set a waypoint.",
        50, "hide")
    row3note:AddWidget(note3, 1)
    card3:AddRow(row3note, 50, 0)

    yOffset = card3:GetNextOffset()

    return yOffset
end)
