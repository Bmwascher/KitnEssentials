-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WarpDepleteForces.lua                               ║
-- ║  GUI: WarpDeplete Forces Tracker                         ║
-- ║  Purpose: Configuration panel for the WarpDepleteForces  ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Local references
local table_insert = table.insert
local ipairs = ipairs

-- Helper to get module
local function GetWDFModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WarpDepleteForces", true)
    end
    return nil
end

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("WarpDepleteForces", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.WarpDepleteForces
    if not db then return yOffset end

    local WDF = GetWDFModule()
    local allWidgets = {}
    local warpDepleteLoaded = WarpDeplete ~= nil

    local function ApplyModuleState(enabled)
        if not WDF then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("WarpDepleteForces")
        else
            KitnEssentials:DisableModule("WarpDepleteForces")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false and warpDepleteLoaded
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "WarpDeplete Forces", yOffset)

    -- WarpDeplete status
    local row0 = GUIFrame:CreateRow(card1.content, 20)
    local statusColor = warpDepleteLoaded and "|cff00ff00" or "|cffff0000"
    local statusText = warpDepleteLoaded and "Detected" or "Not Found"
    local noteWidget = GUIFrame:CreateText(row0,
        "WarpDeplete: " .. statusColor .. statusText .. "|r",
        nil, 20, "hide"
    )
    row0:AddWidget(noteWidget, 1)
    card1:AddRow(row0, 20)

    -- Separator
    local row0sep = GUIFrame:CreateRow(card1.content, 8)
    local sep0 = GUIFrame:CreateSeparator(row0sep)
    row0sep:AddWidget(sep0, 1)
    card1:AddRow(row0sep, 8)

    -- Enable + Tooltip toggles (same row)
    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Forces Tracker", db.Enabled ~= false,
        function(checked)
            if not warpDepleteLoaded then
                checked = false
            end
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Forces Tracker", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)

    local tooltipCheck = GUIFrame:CreateCheckbox(row1, "Show Forces on Tooltip", db.Tooltip ~= false,
        function(checked)
            db.Tooltip = checked
        end
    )
    row1:AddWidget(tooltipCheck, 0.5)
    table_insert(allWidgets, tooltipCheck)
    card1:AddRow(row1, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    -- Info text
    local infoLines = {
        "Restores live pull forces tracking to WarpDeplete enemy forces bar.",
        "Uses fingerprint-based mob identification to bypass 12.0 secret values.",
        "Data: Midnight Season 1 (8 dungeons).",
    }
    local rowHeight = 65
    local row3 = GUIFrame:CreateRow(card1.content, rowHeight)
    local infoWidget = GUIFrame:CreateText(
        row3,
        KE:ColorTextByTheme("How It Works"),
        function() return infoLines end,
        rowHeight,
        "hide"
    )
    row3:AddWidget(infoWidget, 1)
    table_insert(allWidgets, infoWidget)
    card1:AddRow(row3, rowHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
