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
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

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
    local nameplateWidgets = {}
    local nameplateCustomColorWidgets = {}
    local warpDepleteLoaded = WarpDeplete ~= nil

    local function ApplySettings()
        if WDF and WDF.ApplySettings then WDF:ApplySettings() end
    end

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
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        local nameplateEnabled = mainEnabled and db.NameplatePercent == true
        for _, widget in ipairs(nameplateWidgets) do
            if widget.SetEnabled then widget:SetEnabled(nameplateEnabled) end
        end
        local isCustomColor = (db.NameplateColorMode or "theme") == "custom"
        for _, widget in ipairs(nameplateCustomColorWidgets) do
            if widget.SetEnabled then widget:SetEnabled(nameplateEnabled and isCustomColor) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: WarpDeplete+
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "WarpDeplete+", yOffset)

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
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable WarpDeplete+", db.Enabled ~= false,
        function(checked)
            if not warpDepleteLoaded then checked = false end
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "WarpDeplete+", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)

    local tooltipCheck = GUIFrame:CreateCheckbox(row1, "Enemy Count on Tooltip", db.Tooltip ~= false,
        function(checked)
            db.Tooltip = checked
            -- ApplySettings mirrors this to WarpDeplete.db.profile.show-
            -- TooltipCount (inverted) so WD's 5.1.0+ tooltip auto-toggles
            -- off when ours is on and vice-versa.
            ApplySettings()
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
        "Per-mob count on enemy tooltip (12.0.5 API).",
        "Optional % overlay on nameplates (M+ only).",
        "Fixes WarpDeplete death tooltip + class colors.",
    }
    local rowHeight = 80
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

    ---------------------------------------------------------------------------------
    -- Card 2: Nameplate % — Enable
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Nameplate %", yOffset)

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local nameplateCheck = GUIFrame:CreateCheckbox(row2, "Show % on Nameplates",
        db.NameplatePercent == true,
        function(checked)
            db.NameplatePercent = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end
    )
    row2:AddWidget(nameplateCheck, 0.5)
    table_insert(allWidgets, nameplateCheck)

    local combatOnlyCheck = GUIFrame:CreateCheckbox(row2, "Only in Combat",
        db.NameplateCombatOnly ~= false,
        function(checked)
            db.NameplateCombatOnly = checked
            ApplySettings()
        end
    )
    row2:AddWidget(combatOnlyCheck, 0.5)
    table_insert(allWidgets, combatOnlyCheck)
    table_insert(nameplateWidgets, combatOnlyCheck)
    card2:AddRow(row2, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Nameplate % — Position
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Position", yOffset)
    table_insert(allWidgets, card3)
    table_insert(nameplateWidgets, card3)

    local anchorOptions = {
        { key = "CENTER",      text = "Center"       },
        { key = "TOP",         text = "Top"          },
        { key = "BOTTOM",      text = "Bottom"       },
        { key = "LEFT",        text = "Left"         },
        { key = "RIGHT",       text = "Right"        },
        { key = "TOPLEFT",     text = "Top Left"     },
        { key = "TOPRIGHT",    text = "Top Right"    },
        { key = "BOTTOMLEFT",  text = "Bottom Left"  },
        { key = "BOTTOMRIGHT", text = "Bottom Right" },
    }

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local anchorDropdown = GUIFrame:CreateDropdown(row3a, "Anchor", anchorOptions,
        db.NameplateAnchor or "CENTER", 50,
        function(key)
            db.NameplateAnchor = key
            ApplySettings()
        end)
    row3a:AddWidget(anchorDropdown, 1)
    table_insert(allWidgets, anchorDropdown)
    table_insert(nameplateWidgets, anchorDropdown)
    card3:AddRow(row3a, 40)

    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local xSlider = GUIFrame:CreateSlider(row3b, "X Offset", -100, 100, 1,
        db.NameplateXOffset or 25, 60,
        function(val)
            db.NameplateXOffset = val
            ApplySettings()
        end)
    row3b:AddWidget(xSlider, 0.5)
    table_insert(allWidgets, xSlider)
    table_insert(nameplateWidgets, xSlider)

    local ySlider = GUIFrame:CreateSlider(row3b, "Y Offset", -100, 100, 1,
        db.NameplateYOffset or 15, 60,
        function(val)
            db.NameplateYOffset = val
            ApplySettings()
        end)
    row3b:AddWidget(ySlider, 0.5)
    table_insert(allWidgets, ySlider)
    table_insert(nameplateWidgets, ySlider)
    card3:AddRow(row3b, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Nameplate % — Font Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Font Settings", yOffset)
    table_insert(allWidgets, card4)
    table_insert(nameplateWidgets, card4)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.NameplateFontFace or "Expressway", 30,
        function(key)
            db.NameplateFontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)
    table_insert(nameplateWidgets, fontDropdown)

    local sizeSlider = GUIFrame:CreateSlider(row4a, "Size", 8, 20, 1,
        db.NameplateFontSize or 11, 40,
        function(val)
            db.NameplateFontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(sizeSlider, 0.5)
    table_insert(allWidgets, sizeSlider)
    table_insert(nameplateWidgets, sizeSlider)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None"  },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "MONOCHROME",   text = "Monochrome" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList,
        db.NameplateFontOutline or "OUTLINE", 45,
        function(key)
            db.NameplateFontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    table_insert(nameplateWidgets, outlineDropdown)
    card4:AddRow(row4b, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Nameplate % — Colors
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Colors", yOffset)
    table_insert(allWidgets, card5)
    table_insert(nameplateWidgets, card5)

    local row5 = GUIFrame:CreateRow(card5.content, 40)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5, "Color Mode", KE.ColorModeOptions,
        db.NameplateColorMode or "theme", 70,
        function(key)
            db.NameplateColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)
    table_insert(nameplateWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row5, "Custom Color",
        db.NameplateColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.NameplateColor = { r, g, b, a }
            ApplySettings()
        end)
    row5:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(nameplateWidgets, colorPicker)
    table_insert(nameplateCustomColorWidgets, colorPicker)
    card5:AddRow(row5, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
