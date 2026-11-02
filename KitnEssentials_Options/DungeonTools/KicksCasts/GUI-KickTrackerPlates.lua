-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KickTrackerPlates.lua                               ║
-- ║  GUI: Interrupt Tracker > Nameplate Icons                ║
-- ║  Purpose: the nameplate icons' settings tab.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

local HINT = "Target an enemy while this page is open to see two sample icons on its nameplate."

GUIFrame:RegisterContent("KickTrackerPlates", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.KickTracker
    if not db then return yOffset end

    local KT = KitnEssentials and KitnEssentials:GetModule("KickTracker", true)

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("plates", function()
        return db.PlateIcons ~= false
    end)
    manager:SetCondition("premark", function()
        return db.PlateIcons ~= false
    end)
    manager:SetCondition("plateTimer", function()
        return db.PlateIcons ~= false and db.PlateShowTimer ~= false
    end)

    local function ApplySettings()
        if KT and KT.ApplySettings then KT:ApplySettings() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ----------------------------------------------------------------
    -- Nameplate Icons: the display switch, then how the icons behave
    ----------------------------------------------------------------
    local cardPlates = GUIFrame:CreateCard(scrollChild, "Nameplate Icons", yOffset)
    cardPlates:AddHeaderToggle(db.PlateIcons ~= false, function(checked)
        db.PlateIcons = checked
        ApplySettings()
    end)

    local function PlateSwitch(row, key, label, tooltip, refresh)
        local switch = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] ~= false,
            tooltip = tooltip,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if refresh then RefreshStates() end
            end,
        })
        row:AddWidget(switch, 0.5)
        manager:Register(switch, "plates")
    end

    local rowB = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local premarkSwitch = GUIFrame:CreateCheckbox(rowB, "Icons on Marked Mobs", {
        value = db.PlatePremark ~= false,
        tooltip = "Before any kick, a teammate's icon sits on the mob carrying the focus marker " ..
            "they announced, until their own icon is on a nameplate.",
        callback = function(checked) db.PlatePremark = checked; ApplySettings() end,
    })
    rowB:AddWidget(premarkSwitch, 0.5)
    manager:Register(premarkSwitch, "premark")
    PlateSwitch(rowB, "PlateAboveOverlap", "Show Above Overlapping Nameplates",
        "The icons draw over every other nameplate, so an overlapping plate never hides " ..
        "one. When off, an icon stays inside its own nameplate, behind any plate that covers it.")
    cardPlates:AddRow(rowB, Theme.rowHeight)

    -- The card carries the display switch and stays live, so its body
    -- elements gray themselves: a plain card region dims only with its card.
    local rowSep = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeightSeparator)
    local sepPlates = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sepPlates, 1)
    manager:Register(sepPlates, "plates")
    cardPlates:AddRow(rowSep, Theme.rowHeightSeparator)

    local rowL = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    PlateSwitch(rowL, "PlateClassBorder", "Class Color Border")
    PlateSwitch(rowL, "PlateSwipe", "Show Cooldown Swipe")
    cardPlates:AddRow(rowL, Theme.rowHeight)

    local rowIcon = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local plateStyleDropdown = GUIFrame:CreateDropdown(rowIcon, "Icon", {
        options = {
            { key = "kick",  text = "Kick Spell" },
            { key = "spec",  text = "Spec" },
            { key = "class", text = "Class" },
        },
        value = db.PlateIconStyle or "kick",
        callback = function(key) db.PlateIconStyle = key; ApplySettings() end,
    })
    rowIcon:AddWidget(plateStyleDropdown, 0.5)
    manager:Register(plateStyleDropdown, "plates")
    cardPlates:AddRow(rowIcon, Theme.rowHeight)

    local rowHint = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeight)
    local hintText = GUIFrame:CreateText(rowHint, nil, HINT, Theme.rowHeight, "hide")
    rowHint:AddWidget(hintText, 1)
    manager:Register(hintText, "plates")
    cardPlates:AddRow(rowHint, Theme.rowHeight)

    -- EllesmereUI's own test for its kick plate icons; the handle is nil while that addon is not loaded.
    local eui = _G._EMT_AceDB
    local euiKT = eui and eui.profile and eui.profile.kickTracker
    if type(euiKT) == "table" and euiKT.enabled == true and euiKT.showPlates ~= false then
        local rowEui = GUIFrame:CreateRow(cardPlates.content, Theme.rowHeightNote)
        local euiNote = GUIFrame:CreateText(rowEui, nil,
            KE:ColorTextByTheme("-") .. " " .. KE:Gold("EllesmereUI") ..
            "'s Kick Tracker is showing its own nameplate icons too. " ..
            "With both on, two rows sit beside the same health bar: turn one off, or move these with the offsets.",
            Theme.rowHeightNote, "hide")
        rowEui:AddWidget(euiNote, 1)
        manager:Register(euiNote, "plates")
        cardPlates:AddRow(rowEui, Theme.rowHeightNote)
    end

    yOffset = cardPlates:GetNextOffset()

    ----------------------------------------------------------------
    -- Display Settings
    ----------------------------------------------------------------
    local cardPlateDisplay = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(cardPlateDisplay, "plates")

    local rowPD1 = GUIFrame:CreateRow(cardPlateDisplay.content, Theme.rowHeight)
    local plateSizeSlider = GUIFrame:CreateSlider(rowPD1, "Icon Size", {
        min = 16, max = 48, step = 1,
        value = db.PlateIconSize or 30,
        callback = function(val) db.PlateIconSize = val; ApplySettings() end,
    })
    rowPD1:AddWidget(plateSizeSlider, 0.5)
    manager:Register(plateSizeSlider, "plates")

    local plateSpacingSlider = GUIFrame:CreateSlider(rowPD1, "Icon Spacing", {
        min = 0, max = 10, step = 1,
        value = db.PlateSpacing or 1,
        callback = function(val) db.PlateSpacing = val; ApplySettings() end,
    })
    rowPD1:AddWidget(plateSpacingSlider, 0.5)
    manager:Register(plateSpacingSlider, "plates")
    cardPlateDisplay:AddRow(rowPD1, Theme.rowHeight)

    local rowPD2 = GUIFrame:CreateRow(cardPlateDisplay.content, Theme.rowHeight)
    local plateSideDropdown = GUIFrame:CreateDropdown(rowPD2, "Side", {
        options = {
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
        },
        value = db.PlateSide or "LEFT",
        callback = function(key) db.PlateSide = key; ApplySettings() end,
    })
    rowPD2:AddWidget(plateSideDropdown, 0.5)
    manager:Register(plateSideDropdown, "plates")

    local plateGapSlider = GUIFrame:CreateSlider(rowPD2, "Gap to Health Bar", {
        min = 0, max = 20, step = 1,
        value = db.PlateBarGap or 4,
        callback = function(val) db.PlateBarGap = val; ApplySettings() end,
    })
    rowPD2:AddWidget(plateGapSlider, 0.5)
    manager:Register(plateGapSlider, "plates")
    cardPlateDisplay:AddRow(rowPD2, Theme.rowHeight)

    local rowPD3 = GUIFrame:CreateRow(cardPlateDisplay.content, Theme.rowHeightLast)
    local plateXSlider = GUIFrame:CreateSlider(rowPD3, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.PlateOffsetX or 0,
        callback = function(val) db.PlateOffsetX = val; ApplySettings() end,
    })
    rowPD3:AddWidget(plateXSlider, 0.5)
    manager:Register(plateXSlider, "plates")

    local plateYSlider = GUIFrame:CreateSlider(rowPD3, "Y Offset", {
        min = -100, max = 100, step = 1,
        value = db.PlateOffsetY or 0,
        callback = function(val) db.PlateOffsetY = val; ApplySettings() end,
    })
    rowPD3:AddWidget(plateYSlider, 0.5)
    manager:Register(plateYSlider, "plates")
    cardPlateDisplay:AddRow(rowPD3, Theme.rowHeightLast, 0)

    yOffset = cardPlateDisplay:GetNextOffset()

    ----------------------------------------------------------------
    -- Timer Font
    ----------------------------------------------------------------
    local cardTimer = GUIFrame:CreateCard(scrollChild, "Timer Font", yOffset)
    manager:Register(cardTimer, "plates")

    local rowT = GUIFrame:CreateRow(cardTimer.content, Theme.rowHeight)
    PlateSwitch(rowT, "PlateShowTimer", "Show Timer", nil, true)
    local plateTimerSlider = GUIFrame:CreateSlider(rowT, "Timer Size", {
        min = 6, max = 24, step = 1,
        value = db.PlateTimerSize or 13,
        callback = function(val) db.PlateTimerSize = val; ApplySettings() end,
    })
    rowT:AddWidget(plateTimerSlider, 0.5)
    manager:Register(plateTimerSlider, "plateTimer")
    cardTimer:AddRow(rowT, Theme.rowHeight)

    local rowPF = GUIFrame:CreateRow(cardTimer.content, Theme.rowHeightLast)
    local plateFontDropdown = GUIFrame:CreateDropdown(rowPF, "Font", {
        options = KE:AddFollowGlobalFont(fontList),
        value = db.PlateFontFace or KE.FONT_FOLLOW_GLOBAL,
        callback = function(key) db.PlateFontFace = KE:StoredFontFace(key); ApplySettings() end,
        searchable = true,
        isFontPreview = true,
    })
    rowPF:AddWidget(plateFontDropdown, 0.5)
    manager:Register(plateFontDropdown, "plateTimer")

    local plateOutlineDropdown = GUIFrame:CreateDropdown(rowPF, "Font Outline", {
        options = KE:GetFontOutlineOptions(),
        value = KE:NormalizeFontOutline(db.PlateFontOutline or "OUTLINE"),
        callback = function(key) db.PlateFontOutline = key; ApplySettings() end,
    })
    rowPF:AddWidget(plateOutlineDropdown, 0.5)
    manager:Register(plateOutlineDropdown, "plateTimer")
    cardTimer:AddRow(rowPF, Theme.rowHeightLast, 0)

    yOffset = cardTimer:GetNextOffset()

    RefreshStates()
    return yOffset
end)
