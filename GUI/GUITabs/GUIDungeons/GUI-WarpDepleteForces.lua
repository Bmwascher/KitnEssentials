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

local pairs = pairs

local function GetWDFModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WarpDepleteForces", true)
    end
    return nil
end

GUIFrame:RegisterContent("WarpDepleteForces", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.WarpDepleteForces
    if not db then return yOffset end

    local WDF = GetWDFModule()
    local warpDepleteLoaded = WarpDeplete ~= nil

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("nameplate", function()
        return db.NameplatePercent == true
    end)
    manager:SetCondition("nameplateCustomColor", function()
        return db.NameplatePercent == true
            and (db.NameplateColorMode or "theme") == "custom"
    end)

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

    local function RefreshStates()
        local mainEnabled = db.Enabled ~= false and warpDepleteLoaded
        manager:UpdateAll(mainEnabled)
    end

    ----------------------------------------------------------------
    -- Card 1: WarpDeplete+
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "WarpDeplete+", yOffset)

    -- WarpDeplete status (no SetEnabled — display-only)
    local row0 = GUIFrame:CreateRow(card1.content, 20)
    local statusColor = warpDepleteLoaded and "|cff00ff00" or "|cffff0000"
    local statusText = warpDepleteLoaded and "Detected" or "Not Found"
    local noteWidget = GUIFrame:CreateText(row0,
        "WarpDeplete: " .. statusColor .. statusText .. "|r",
        nil, 20, "hide"
    )
    row0:AddWidget(noteWidget, 1)
    card1:AddRow(row0, 20)

    local row0sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep0 = GUIFrame:CreateSeparator(row0sep)
    row0sep:AddWidget(sep0, 1)
    card1:AddRow(row0sep, Theme.rowHeightSeparator)

    -- Enable + Tooltip toggles
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable WarpDeplete+", {
        value = db.Enabled ~= false,
        callback = function(checked)
            if not warpDepleteLoaded then checked = false end
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "WarpDeplete+",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)

    local tooltipCheck = GUIFrame:CreateCheckbox(row1, "Enemy Count on Tooltip", {
        value = db.Tooltip ~= false,
        callback = function(checked)
            db.Tooltip = checked
            -- ApplySettings mirrors this to WarpDeplete.db.profile.show-
            -- TooltipCount (inverted) so WD's 5.1.0+ tooltip auto-toggles
            -- off when ours is on and vice-versa.
            ApplySettings()
        end,
    })
    row1:AddWidget(tooltipCheck, 0.5)
    manager:Register(tooltipCheck, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local row1sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card1:AddRow(row1sep, Theme.rowHeightSeparator)

    -- Info text
    local infoLines = {
        "Per-mob count on enemy tooltip (12.0.5 API).",
        "Optional % overlay on nameplates (M+ only).",
        "Fixes WarpDeplete death tooltip + class colors.",
    }
    local infoHeight = 80
    local row3 = GUIFrame:CreateRow(card1.content, infoHeight)
    local infoWidget = GUIFrame:CreateText(
        row3,
        KE:ColorTextByTheme("How It Works"),
        function() return infoLines end,
        infoHeight,
        "hide"
    )
    row3:AddWidget(infoWidget, 1)
    manager:Register(infoWidget, "all")
    card1:AddRow(row3, infoHeight, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Nameplate % — Enable
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Nameplate %", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local nameplateCheck = GUIFrame:CreateCheckbox(row2, "Show % on Nameplates", {
        value = db.NameplatePercent == true,
        callback = function(checked)
            db.NameplatePercent = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row2:AddWidget(nameplateCheck, 0.5)
    manager:Register(nameplateCheck, "all")

    local combatOnlyCheck = GUIFrame:CreateCheckbox(row2, "Only in Combat", {
        value = db.NameplateCombatOnly ~= false,
        callback = function(checked)
            db.NameplateCombatOnly = checked
            ApplySettings()
        end,
    })
    row2:AddWidget(combatOnlyCheck, 0.5)
    manager:Register(combatOnlyCheck, "nameplate")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Nameplate % — Position
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Position", yOffset)
    manager:Register(card3, "nameplate")

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

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local anchorDropdown = GUIFrame:CreateDropdown(row3a, "Anchor", {
        options = anchorOptions,
        value = db.NameplateAnchor or "CENTER",
        callback = function(key)
            db.NameplateAnchor = key
            ApplySettings()
        end,
    })
    row3a:AddWidget(anchorDropdown, 1)
    manager:Register(anchorDropdown, "nameplate")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local xSlider = GUIFrame:CreateSlider(row3b, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.NameplateXOffset or 25,
        callback = function(val)
            db.NameplateXOffset = val
            ApplySettings()
        end,
    })
    row3b:AddWidget(xSlider, 0.5)
    manager:Register(xSlider, "nameplate")

    local ySlider = GUIFrame:CreateSlider(row3b, "Y Offset", {
        min = -100, max = 100, step = 1,
        value = db.NameplateYOffset or 15,
        callback = function(val)
            db.NameplateYOffset = val
            ApplySettings()
        end,
    })
    row3b:AddWidget(ySlider, 0.5)
    manager:Register(ySlider, "nameplate")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Nameplate % — Font Settings
    -- (Custom card: WD nameplate uses MONOCHROME outline option, not the
    -- standard NONE/OUTLINE/THICKOUTLINE/SOFTOUTLINE set, so we don't use
    -- the shared FontSettingsCard.)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Font Settings", yOffset)
    manager:Register(card4, "nameplate")

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", {
        options = fontList,
        value = db.NameplateFontFace or "Expressway",
        callback = function(key)
            db.NameplateFontFace = key
            ApplySettings()
        end,
        searchable = true,
        isFontPreview = true,
    })
    row4a:AddWidget(fontDropdown, 0.5)
    manager:Register(fontDropdown, "nameplate")

    local sizeSlider = GUIFrame:CreateSlider(row4a, "Size", {
        min = 8, max = 20, step = 1,
        value = db.NameplateFontSize or 11,
        callback = function(val)
            db.NameplateFontSize = val
            ApplySettings()
        end,
    })
    row4a:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "nameplate")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local outlineList = {
        { key = "NONE",         text = "None"  },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "MONOCHROME",   text = "Monochrome" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", {
        options = outlineList,
        value = db.NameplateFontOutline or "OUTLINE",
        callback = function(key)
            db.NameplateFontOutline = key
            ApplySettings()
        end,
    })
    row4b:AddWidget(outlineDropdown, 1)
    manager:Register(outlineDropdown, "nameplate")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Nameplate % — Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Nameplate % — Colors", yOffset)
    manager:Register(card5, "nameplate")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.NameplateColorMode or "theme",
        callback = function(key)
            db.NameplateColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row5:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "nameplate")

    local colorPicker = GUIFrame:CreateColorPicker(row5, "Custom Color", {
        color = db.NameplateColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.NameplateColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "nameplateCustomColor")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Instance Reset Announcer
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Instance Reset Announcer", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local irEnableCheck = GUIFrame:CreateCheckbox(row6a, "Announce on /reset to party/raid", {
        value = db.InstanceResetEnabled ~= false,
        callback = function(checked)
            db.InstanceResetEnabled = checked
            ApplySettings()
        end,
    })
    row6a:AddWidget(irEnableCheck, 1)
    manager:Register(irEnableCheck, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local irMessageBox = GUIFrame:CreateEditBox(row6b, "Message", {
        value = db.InstanceResetMessage or "Instance reset!",
        callback = function(text) db.InstanceResetMessage = text end,
    })
    row6b:AddWidget(irMessageBox, 1)
    manager:Register(irMessageBox, "all")
    card6:AddRow(row6b, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
