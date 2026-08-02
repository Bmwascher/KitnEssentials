-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-UIWidgets.lua                                        ║
-- ║  GUI: UI Widgets                                          ║
-- ║  Purpose: Configuration panel for the                     ║
-- ║           UIWidgets module.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

-- Localization Setup
local pairs = pairs
local table_insert = table.insert
local table_sort = table.sort

local OUTLINE_OPTIONS = KE:GetFontOutlineOptions()

GUIFrame:RegisterContent("SkinBlizzardFramesWidgets", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.UIWidgets
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    -- Apply settings through module
    local function ApplySettings()
        local UIW = KitnEssentials:GetModule("UIWidgets", true)
        if UIW and UIW:IsEnabled() then UIW:ApplySettings() end
    end

    local barDB = db.StatusBar
    local textDB = db.TextWidget

    manager:SetCondition("statusbar", function()
        return barDB.Enabled ~= false
    end)
    manager:SetCondition("textwidget", function()
        return textDB.Enabled ~= false
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- Build font list
    local function GetFontList()
        local fontList = {}
        if LSM then
            for name in pairs(LSM:HashTable("font")) do
                table_insert(fontList, { key = name, text = name })
            end
            table_sort(fontList, function(a, b) return a.text < b.text end)
        else
            table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
        end
        return fontList
    end
    local fontList = GetFontList()

    ----------------------------------------------------------------
    -- Card 1: Master Toggle
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "UI Widgets", yOffset)

    -- Module enable lives in the card header (v3.5.183 UX standard).
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if not checked then KE:SkinningReloadPrompt() end -- v3.5.691: un-skin needs /reload
        if checked then
            KitnEssentials:EnableModule("UIWidgets")
            ApplySettings()
        else
            KitnEssentials:DisableModule("UIWidgets")
        end
        RefreshStates()
    end)

    -- Disabled modules collapse to the header bar alone (v3.5.188):
    -- settings only render while the module is enabled.
    if db.Enabled == false then
        yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall
    else
        card1:AddLabel("Restyles Blizzard's status bar and text widgets (M+ timer, power bars, event banners).")

        yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

        ----------------------------------------------------------------
        -- Card 2: Global Font Settings
        ----------------------------------------------------------------
        local card2 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
        manager:Register(card2, "all")

        -- Font Dropdown
        local row2a = GUIFrame:CreateRow(card2.content, 36)
        local fontDropdown = GUIFrame:CreateDropdown(row2a, "Font", {
            options = fontList,
            value = db.FontFace or "Expressway",
            callback = function(key)
                db.FontFace = key
                ApplySettings()
            end,
            searchable = true,
            isFontPreview = true
        })
        row2a:AddWidget(fontDropdown, 0.5)
        manager:Register(fontDropdown, "all")

        -- Outline Dropdown
        local outlineDropdown = GUIFrame:CreateDropdown(row2a, "Outline", {
            options = OUTLINE_OPTIONS,
            value = db.FontOutline or "OUTLINE",
            callback = function(key)
                db.FontOutline = key
                ApplySettings()
            end
        })
        row2a:AddWidget(outlineDropdown, 0.5)
        manager:Register(outlineDropdown, "all")
        card2:AddRow(row2a, 36)

        yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

        ----------------------------------------------------------------
        -- Card 3: Status Bar Widgets
        ----------------------------------------------------------------
        local card3 = GUIFrame:CreateCard(scrollChild, "Status Bar Widgets", yOffset)
        manager:Register(card3, "all")

        -- Enable toggle
        local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local enableBarCheck = GUIFrame:CreateCheckbox(row3a, "Enable Status Bar Styling", {
            value = barDB.Enabled ~= false,
            callback = function(checked)
                barDB.Enabled = checked
                if not checked then KE:SkinningReloadPrompt() end -- v3.5.691: un-skin needs /reload
                ApplySettings()
                RefreshStates()
            end,
        })
        row3a:AddWidget(enableBarCheck, 0.5)
        manager:Register(enableBarCheck, "all")

        -- Width slider (0 = default/auto)
        local barWidthSlider = GUIFrame:CreateSlider(row3a, "Width (0=Auto)", {
            min = 0,
            max = 400,
            step = 1,
            value = barDB.Width or 0,
            labelWidth = 80,
            callback = function(val)
                barDB.Width = val
                ApplySettings()
            end
        })
        row3a:AddWidget(barWidthSlider, 0.5)
        manager:Register(barWidthSlider, "statusbar")
        card3:AddRow(row3a, Theme.rowHeight)

        -- Style Label toggle
        local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local styleLabelCheck = GUIFrame:CreateCheckbox(row3b, "Style Label Text", {
            value = barDB.StyleLabel ~= false,
            callback = function(checked)
                barDB.StyleLabel = checked
                ApplySettings()
            end,
        })
        row3b:AddWidget(styleLabelCheck, 0.5)
        manager:Register(styleLabelCheck, "statusbar")

        -- Style Bar Text toggle
        local styleBarTextCheck = GUIFrame:CreateCheckbox(row3b, "Style Bar Text", {
            value = barDB.StyleBarText ~= false,
            callback = function(checked)
                barDB.StyleBarText = checked
                ApplySettings()
            end,
        })
        row3b:AddWidget(styleBarTextCheck, 0.5)
        manager:Register(styleBarTextCheck, "statusbar")
        card3:AddRow(row3b, Theme.rowHeight)

        -- Font Size Sliders
        local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local labelSizeSlider = GUIFrame:CreateSlider(row3c, "Label Size", {
            min = 8,
            max = 24,
            step = 1,
            value = barDB.LabelSize or 14,
            labelWidth = 60,
            callback = function(val)
                barDB.LabelSize = val
                ApplySettings()
            end
        })
        row3c:AddWidget(labelSizeSlider, 0.5)
        manager:Register(labelSizeSlider, "statusbar")

        local barTextSizeSlider = GUIFrame:CreateSlider(row3c, "Bar Text Size", {
            min = 8,
            max = 24,
            step = 1,
            value = barDB.BarTextSize or 12,
            labelWidth = 70,
            callback = function(val)
                barDB.BarTextSize = val
                ApplySettings()
            end
        })
        row3c:AddWidget(barTextSizeSlider, 0.5)
        manager:Register(barTextSizeSlider, "statusbar")
        card3:AddRow(row3c, Theme.rowHeight)

        -- Separator
        local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
        local sep1 = GUIFrame:CreateSeparator(row3sep)
        row3sep:AddWidget(sep1, 1)
        manager:Register(sep1, "statusbar")
        card3:AddRow(row3sep, Theme.rowHeightSeparator)

        -- Strip Textures toggle
        local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
        local stripTexturesCheck = GUIFrame:CreateCheckbox(row3d, "Strip Blizzard Textures & Add Backdrop", {
            value = barDB.StripTextures ~= false,
            callback = function(checked)
                barDB.StripTextures = checked
                ApplySettings()
            end,
        })
        row3d:AddWidget(stripTexturesCheck, 1)
        manager:Register(stripTexturesCheck, "statusbar")
        card3:AddRow(row3d, Theme.rowHeight)

        -- Backdrop Color
        local row3e = GUIFrame:CreateRow(card3.content, 36)
        local backdropColorPicker = GUIFrame:CreateColorPicker(row3e, "Backdrop Color", {
            color = barDB.BackdropColor,
            callback = function(r, g, b, a)
                barDB.BackdropColor = { r, g, b, a }
                ApplySettings()
            end
        })
        row3e:AddWidget(backdropColorPicker, 0.5)
        manager:Register(backdropColorPicker, "statusbar")

        -- Border Color
        local borderColorPicker = GUIFrame:CreateColorPicker(row3e, "Border Color", {
            color = barDB.BorderColor,
            callback = function(r, g, b, a)
                barDB.BorderColor = { r, g, b, a }
                ApplySettings()
            end
        })
        row3e:AddWidget(borderColorPicker, 0.5)
        manager:Register(borderColorPicker, "statusbar")
        card3:AddRow(row3e, 36)

        yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

        ----------------------------------------------------------------
        -- Card 4: Text Widgets
        ----------------------------------------------------------------
        local card4 = GUIFrame:CreateCard(scrollChild, "Text Widgets", yOffset)
        manager:Register(card4, "all")

        -- Enable toggle and Style Text
        local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
        local enableTextCheck = GUIFrame:CreateCheckbox(row4a, "Enable Text Widget Styling", {
            value = textDB.Enabled ~= false,
            callback = function(checked)
                textDB.Enabled = checked
                if not checked then KE:SkinningReloadPrompt() end -- v3.5.691: un-skin needs /reload
                ApplySettings()
                RefreshStates()
            end,
        })
        row4a:AddWidget(enableTextCheck, 0.5)
        manager:Register(enableTextCheck, "all")

        -- Style Text toggle
        local styleTextCheck = GUIFrame:CreateCheckbox(row4a, "Style Text", {
            value = textDB.StyleText ~= false,
            callback = function(checked)
                textDB.StyleText = checked
                ApplySettings()
            end,
        })
        row4a:AddWidget(styleTextCheck, 0.5)
        manager:Register(styleTextCheck, "textwidget")
        card4:AddRow(row4a, Theme.rowHeight)

        -- Width slider (0 = default/auto)
        local row4width = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
        local textWidthSlider = GUIFrame:CreateSlider(row4width, "Width (0=Auto)", {
            min = 0,
            max = 400,
            step = 1,
            value = textDB.Width or 0,
            labelWidth = 80,
            callback = function(val)
                textDB.Width = val
                ApplySettings()
            end
        })
        row4width:AddWidget(textWidthSlider, 1)
        manager:Register(textWidthSlider, "textwidget")
        card4:AddRow(row4width, Theme.rowHeight)

        -- Font Size Slider
        local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
        local textSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", {
            min = 8,
            max = 24,
            step = 1,
            value = textDB.Size or 14,
            labelWidth = 60,
            callback = function(val)
                textDB.Size = val
                ApplySettings()
            end
        })
        row4b:AddWidget(textSizeSlider, 1)
        manager:Register(textSizeSlider, "textwidget")
        card4:AddRow(row4b, Theme.rowHeight)

        yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

        RefreshStates()
    end

    ----------------------------------------------------------------
    -- Alert Frames (independent module — hosted on this page; see
    -- .superpowers/sdd/2026-08-01-aes-a7-3-qol-batch/followup-a-alertframes-brief.md)
    ----------------------------------------------------------------
    local function GetModule()
        if KitnEssentials then
            return KitnEssentials:GetModule("AlertFrames", true)
        end
        return nil
    end

    local afDB = KE.db and KE.db.profile.AlertFrames
    if not afDB then return yOffset end

    local AF = GetModule()
    local afManager = GUIFrame:CreateWidgetStateManager()
    afManager:SetCondition("toasts", function() return afDB.MoveEventToasts == true end)

    local function RefreshAFStates()
        afManager:UpdateAll(afDB.Enabled ~= false)
    end

    local function ApplyState(enabled)
        if not AF then return end
        afDB.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("AlertFrames")
        else KitnEssentials:DisableModule("AlertFrames") end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local afCard1 = GUIFrame:CreateCard(scrollChild, "Alert Frames", yOffset)
    afCard1:AddHeaderToggle(afDB.Enabled ~= false, function(checked)
        afDB.Enabled = checked
        ApplyState(checked)
        -- The AdjustAnchors replacements and hooksecurefunc hooks this module
        -- installs cannot be undone (Modules/QoL/AlertFrames.lua header taint
        -- note): turning the toggle off would otherwise leave the toast stack
        -- overridden by a module that reports itself off.
        if not checked then
            KE:CreateReloadPrompt("Turning off the alert anchor requires a UI reload to give the toasts back to Blizzard.")
        end
        KE:Print("Alert Frames: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteHeight = 70
    local noteRow = GUIFrame:CreateRow(afCard1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") ..
        " Moves the whole Blizzard toast stack — loot, achievements, dungeon " ..
        "completion — to a spot you choose. The stack grows upward when the " ..
        "anchor is in the lower half of the screen and downward when it is in " ..
        "the upper half. Use /kes edit to drag it. Turning it off needs a reload.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    afCard1:AddRow(noteRow, noteHeight, 0)

    yOffset = afCard1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if afDB.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Alert Stack Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Alert Stack Position",
        db = afDB,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            if AF then AF:ApplyPosition() end
        end,
    })

    if posCard.positionWidgets then
        afManager:RegisterGroup(posCard.positionWidgets, "all")
    end
    afManager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Event Toasts
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Event Toasts", yOffset)
    afManager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local moveToastsCheck = GUIFrame:CreateCheckbox(row3, "Move Recipe and Level-Up Banners", {
        value = afDB.MoveEventToasts == true,
        callback = function(checked)
            afDB.MoveEventToasts = checked
            if AF then AF:ApplySettings() end
            RefreshAFStates()
        end,
    })
    row3:AddWidget(moveToastsCheck, 1)
    afManager:Register(moveToastsCheck, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Event Toast Position
    ----------------------------------------------------------------
    -- positionKey routes this card at db.EventToastPosition instead of the
    -- default db.Position (Card 2's table) -- GUI-PositionCard.lua:226,245.
    -- Root keys (anchorFrameType/ParentFrame/Strata) live at the db ROOT
    -- regardless of positionKey (GUI-PositionCard.lua:456-460), so they also
    -- need their own names or this card would still clobber Card 2's anchor
    -- type/parent/strata. Fix round 1 finding: db.EventToastPosition is
    -- already seeded by Task 1's defaults (Core/Defaults.lua:1276-1291), and
    -- the three EventToast* root keys are plain scalars that default safely
    -- to "SCREEN"/"HIGH" when unset (GUI-PositionCard.lua:492,522) the same
    -- way Card 2's un-seeded root keys already do -- so no Core/Defaults.lua
    -- change is needed for either. Same shape as HealerMana's Raid/Dungeon
    -- split (GUI-HealerMana.lua:151-161).
    local toastPosCard, toastPosOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Event Toast Position",
        db = afDB,
        positionKey = "EventToastPosition",
        dbKeys = {
            anchorFrameType = "EventToastAnchorFrameType",
            anchorFrameFrame = "EventToastParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "EventToastStrata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = function()
            if AF then AF:ApplyEventToastPosition() end
        end,
    })

    if toastPosCard.positionWidgets then
        afManager:RegisterGroup(toastPosCard.positionWidgets, "toasts")
    end
    afManager:Register(toastPosCard, "toasts")
    yOffset = toastPosOffset

    RefreshAFStates()
    return yOffset
end)
