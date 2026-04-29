-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatTimer.lua                                     ║
-- ║  GUI: Combat Timer                                       ║
-- ║  Purpose: Configuration panel for the CombatTimer module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("CombatTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatTimer
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    db.Backdrop = db.Backdrop or {}

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("backdrop", function()
        return db.Backdrop and db.Backdrop.Enabled == true
    end)

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("CombatTimer", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CombatTimer", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatTimer")
        else
            KitnEssentials:DisableModule("CombatTimer")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Timer", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Timer", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Combat Timer",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Format (Print to Chat + Format + Bracket Style)
    ----------------------------------------------------------------
    local cardFormat = GUIFrame:CreateCard(scrollChild, "Format", yOffset)
    manager:Register(cardFormat, "all")

    local rowFchat = GUIFrame:CreateRow(cardFormat.content, Theme.rowHeight)
    local chatCheck = GUIFrame:CreateCheckbox(rowFchat, "Print Duration to Chat", {
        value = db.ShowChatMessage ~= false,
        callback = function(checked) db.ShowChatMessage = checked; ApplySettings() end,
    })
    rowFchat:AddWidget(chatCheck, 1)
    manager:Register(chatCheck, "all")
    cardFormat:AddRow(rowFchat, Theme.rowHeight)

    local rowFsep = GUIFrame:CreateRow(cardFormat.content, Theme.rowHeightSeparator)
    local sepF = GUIFrame:CreateSeparator(rowFsep)
    rowFsep:AddWidget(sepF, 1)
    manager:Register(sepF, "all")
    cardFormat:AddRow(rowFsep, Theme.rowHeightSeparator)

    local rowF = GUIFrame:CreateRow(cardFormat.content, Theme.rowHeightLast)
    local formatDropdown = GUIFrame:CreateDropdown(rowF, "Format", {
        options = { ["MM:SS"] = "MM:SS", ["MM:SS:MS"] = "MM:SS:MS" },
        value = db.Format or "MM:SS",
        callback = function(key) db.Format = key; ApplySettings() end,
    })
    rowF:AddWidget(formatDropdown, 0.5)
    manager:Register(formatDropdown, "all")

    local bracketDropdown = GUIFrame:CreateDropdown(rowF, "Bracket Style", {
        options = {
            ["square"] = "Square [00:00]",
            ["round"]  = "Round (00:00)",
            ["none"]   = "None 00:00",
        },
        value = db.BracketStyle or "square",
        callback = function(key) db.BracketStyle = key; ApplySettings() end,
    })
    rowF:AddWidget(bracketDropdown, 0.5)
    manager:Register(bracketDropdown, "all")
    cardFormat:AddRow(rowF, Theme.rowHeightLast, 0)

    yOffset = cardFormat:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local inCombatColor = GUIFrame:CreateColorPicker(row4a, "In Combat Color", {
        color = db.ColorInCombat or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.ColorInCombat = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(inCombatColor, 0.5)
    manager:Register(inCombatColor, "all")

    local outCombatColor = GUIFrame:CreateColorPicker(row4a, "Out of Combat Color", {
        color = db.ColorOutOfCombat or { 1, 1, 1, 0.7 },
        callback = function(r, g, b, a)
            db.ColorOutOfCombat = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(outCombatColor, 0.5)
    manager:Register(outCombatColor, "all")
    card4:AddRow(row4a, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Backdrop
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local backdropCheck = GUIFrame:CreateCheckbox(row5a, "Enable Backdrop", {
        value = db.Backdrop.Enabled ~= false,
        callback = function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(backdropCheck, 1)
    manager:Register(backdropCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local bgWidth = GUIFrame:CreateSlider(row5b, "Width", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgWidth or 100,
        callback = function(val) db.Backdrop.bgWidth = val; ApplySettings() end,
    })
    row5b:AddWidget(bgWidth, 0.4)
    manager:Register(bgWidth, "backdrop")

    local bgHeight = GUIFrame:CreateSlider(row5b, "Height", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgHeight or 40,
        callback = function(val) db.Backdrop.bgHeight = val; ApplySettings() end,
    })
    row5b:AddWidget(bgHeight, 0.4)
    manager:Register(bgHeight, "backdrop")

    local bgColor = GUIFrame:CreateColorPicker(row5b, "Color", {
        color = db.Backdrop.Color or { 0, 0, 0, 0.6 },
        callback = function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(bgColor, 0.2)
    manager:Register(bgColor, "backdrop")
    card5:AddRow(row5b, Theme.rowHeight)

    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sepBg = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sepBg, 1)
    manager:Register(sepBg, "backdrop")
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local borderSize = GUIFrame:CreateSlider(row5c, "Border Size", {
        min = 1, max = 10, step = 1,
        value = db.Backdrop.BorderSize or 1,
        callback = function(val) db.Backdrop.BorderSize = val; ApplySettings() end,
    })
    row5c:AddWidget(borderSize, 0.8)
    manager:Register(borderSize, "backdrop")

    local borderColor = GUIFrame:CreateColorPicker(row5c, "Border Color", {
        color = db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5c:AddWidget(borderColor, 0.2)
    manager:Register(borderColor, "backdrop")
    card5:AddRow(row5c, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
