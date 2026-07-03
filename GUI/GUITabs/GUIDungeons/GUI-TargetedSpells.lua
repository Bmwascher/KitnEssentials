-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TargetedSpells.lua                                  ║
-- ║  GUI: Targeted Spells                                    ║
-- ║  Purpose: Configuration panel for the TargetedSpells     ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme

GUIFrame:RegisterContent("TargetedSpells", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TargetedSpells
    if not db then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function GetModule()
        return KitnEssentials and KitnEssentials:GetModule("TargetedSpells", true)
    end

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function Rebuild()
        local mod = GetModule()
        if mod and mod.RebuildEntries then mod:RebuildEntries() end
    end

    local function ApplyModuleState(enabled)
        local mod = GetModule()
        if not mod then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("TargetedSpells")
        else
            KitnEssentials:DisableModule("TargetedSpells")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Targeted Spells", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Targeted Spells", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Targeted Spells",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 65)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows enemy casts aimed at YOU as icon + countdown + icon entries.\n" ..
        KE:ColorTextByTheme("-") .. " Casts over 60 seconds (junk NPC channels) are hidden automatically.\n" ..
        KE:ColorTextByTheme("-") .. " Off-screen casters need the nameplateShowOffscreen CVar (prompted on enable).",
        65, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 65, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint  = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset    = "XOffset",
            yOffset    = "YOffset",
            strata     = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        onChangeCallback    = function()
            local mod = GetModule()
            if mod and mod.ApplyPosition then mod:ApplyPosition() end
        end,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings (structural: countdown font -> rebuild)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = false,   -- widget-managed countdown text (spec constraint 3)
        onChangeCallback = Rebuild,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: Layout
    ----------------------------------------------------------------
    local cardL = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    manager:Register(cardL, "all")

    local rowL1 = GUIFrame:CreateRow(cardL.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(rowL1, "Icon Size", {
        min = 20, max = 80, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; Rebuild() end,
    })
    rowL1:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")

    local gapSlider = GUIFrame:CreateSlider(rowL1, "Gap", {
        min = 0, max = 20, step = 1,
        value = db.Gap or 2,
        callback = function(val) db.Gap = val; Rebuild() end,
    })
    rowL1:AddWidget(gapSlider, 0.5)
    manager:Register(gapSlider, "all")
    cardL:AddRow(rowL1, Theme.rowHeight)

    local rowL2 = GUIFrame:CreateRow(cardL.content, Theme.rowHeightLast)
    local growDrop = GUIFrame:CreateDropdown(rowL2, "Grow Direction", {
        options = { { key = "DOWN", text = "Down" }, { key = "UP", text = "Up" } },
        value = db.Grow or "DOWN",
        callback = function(key) db.Grow = key; Rebuild() end,
    })
    rowL2:AddWidget(growDrop, 0.5)
    manager:Register(growDrop, "all")

    local maxSlider = GUIFrame:CreateSlider(rowL2, "Max Entries", {
        min = 1, max = 10, step = 1,
        value = db.MaxIcons or 10,
        callback = function(val) db.MaxIcons = val; Rebuild() end,
    })
    rowL2:AddWidget(maxSlider, 0.5)
    manager:Register(maxSlider, "all")
    cardL:AddRow(rowL2, Theme.rowHeightLast, 0)

    yOffset = cardL:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Features
    ----------------------------------------------------------------
    local cardF = GUIFrame:CreateCard(scrollChild, "Features", yOffset)
    manager:Register(cardF, "all")

    local rowF1 = GUIFrame:CreateRow(cardF.content, Theme.rowHeight)
    local swipeCheck = GUIFrame:CreateCheckbox(rowF1, "Cooldown Swipe", {
        value = db.ShowSwipe ~= false,
        callback = function(checked) db.ShowSwipe = checked; ApplySettings() end,
    })
    rowF1:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local glowCheck = GUIFrame:CreateCheckbox(rowF1, "Glow Important Spells", {
        value = db.GlowImportant ~= false,
        callback = function(checked) db.GlowImportant = checked; ApplySettings() end,
    })
    rowF1:AddWidget(glowCheck, 0.5)
    manager:Register(glowCheck, "all")
    cardF:AddRow(rowF1, Theme.rowHeight)

    local rowF2 = GUIFrame:CreateRow(cardF.content, Theme.rowHeightLast)
    local interruptCheck = GUIFrame:CreateCheckbox(rowF2, "Indicate Interrupts", {
        value = db.IndicateInterrupts ~= false,
        callback = function(checked) db.IndicateInterrupts = checked; ApplySettings() end,
    })
    rowF2:AddWidget(interruptCheck, 1)
    manager:Register(interruptCheck, "all")
    cardF:AddRow(rowF2, Theme.rowHeightLast, 0)

    yOffset = cardF:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Show In (content gating)
    ----------------------------------------------------------------
    local cardC = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    manager:Register(cardC, "all")

    local function contentCheckbox(row, label, key, defaultOn)
        local widget = GUIFrame:CreateCheckbox(row, label, {
            value = defaultOn and (db[key] ~= false) or (db[key] == true),
            callback = function(checked) db[key] = checked; ApplySettings() end,
        })
        manager:Register(widget, "all")
        return widget
    end

    local rowC1 = GUIFrame:CreateRow(cardC.content, Theme.rowHeight)
    rowC1:AddWidget(contentCheckbox(rowC1, "Dungeons", "ShowInDungeons", true), 0.33)
    rowC1:AddWidget(contentCheckbox(rowC1, "Delves", "ShowInDelves", true), 0.33)
    rowC1:AddWidget(contentCheckbox(rowC1, "Raids", "ShowInRaids", false), 0.33)
    cardC:AddRow(rowC1, Theme.rowHeight)

    local rowC2 = GUIFrame:CreateRow(cardC.content, Theme.rowHeightLast)
    rowC2:AddWidget(contentCheckbox(rowC2, "Open World", "ShowInOpenWorld", false), 0.5)
    rowC2:AddWidget(contentCheckbox(rowC2, "Arenas / Battlegrounds", "ShowInPvP", false), 0.5)
    cardC:AddRow(rowC2, Theme.rowHeightLast, 0)

    yOffset = cardC:GetNextOffset()

    RefreshStates()
    return yOffset
end)
