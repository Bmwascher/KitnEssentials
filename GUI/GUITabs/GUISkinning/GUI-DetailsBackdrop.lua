-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DetailsBackdrop.lua                                 ║
-- ║  GUI: Details Backdrop                                   ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           DetailsBackdrop module.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetDetailsBackdropModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinDetailsBackdrop", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinDetails", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Details
    if not db then return yOffset end

    local DBG = GetDetailsBackdropModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    local posCard

    if GUIFrame.pendingContext then
        local ctx = GUIFrame.pendingContext
        if ctx == "bgOne" or ctx == "bgTwo" then
            db.currentEdit = ctx
        end
        GUIFrame.pendingContext = nil
    end

    local curEdit = db.currentEdit or "bgOne"

    local function GetCurrentBackdropDB()
        if curEdit == "bgTwo" then
            return db.backDropTwo
        else
            return db.backDropOne
        end
    end

    local function ApplyAll()
        if DBG then
            DBG:UpdateDetailsBackdropOne()
            DBG:UpdateDetailsBackdropTwo()
        end
    end

    local function ApplySettings()
        if DBG then
            if curEdit == "bgOne" then
                DBG:UpdateDetailsBackdropOne()
            else
                DBG:UpdateDetailsBackdropTwo()
            end
        end
    end

    local function ApplyDetailsBackdropState(enabled)
        if not DBG then return end
        DBG.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinDetailsBackdrop")
        else
            KitnEssentials:DisableModule("SkinDetailsBackdrop")
        end
    end

    -- "all"        → master AND per-backdrop enabled (default for most widgets)
    -- "masterOnly" → master only (currentEdit dropdown, perEnableCheck)
    -- "autoSize"   → master AND perEnabled AND autoSize ON
    -- "manualSize" → master AND perEnabled AND autoSize OFF
    manager:SetCondition("all", function()
        return GetCurrentBackdropDB().Enabled ~= false
    end)
    manager:SetCondition("autoSize", function()
        local cur = GetCurrentBackdropDB()
        return cur.Enabled ~= false and cur.autoSize == true
    end)
    manager:SetCondition("manualSize", function()
        local cur = GetCurrentBackdropDB()
        return cur.Enabled ~= false and not cur.autoSize
    end)

    local function RefreshStates()
        local mainEnabled = db.Enabled ~= false
        manager:UpdateAll(mainEnabled)
        if posCard and posCard.SetAnchorsOnlyEnabled then
            local cur = GetCurrentBackdropDB()
            local bothEnabled = mainEnabled and cur.Enabled ~= false
            posCard:SetAnchorsOnlyEnabled(bothEnabled and not cur.autoSize)
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Edit Selector + Per-backdrop Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Details Backdrop", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Details Backdrop", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyDetailsBackdropState(checked)
            RefreshStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
        msgPopup = true,
        msgText = "Details Backdrop",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)

    local editList = {
        { key = "bgOne", text = "Backdrop One" },
        { key = "bgTwo", text = "Backdrop Two" },
    }
    local editDropdown = GUIFrame:CreateDropdown(row1, "Select Backdrop To Edit", {
        options = editList,
        value = curEdit,
        callback = function(key)
            curEdit = key
            db.currentEdit = key
            GUIFrame:RefreshContent()
        end,
    })
    row1:AddWidget(editDropdown, 0.5)
    manager:Register(editDropdown, "masterOnly")
    card1:AddRow(row1, Theme.rowHeight)

    local row1sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    card1:AddRow(row1sep, Theme.rowHeightSeparator)

    local backdropLabel = curEdit == "bgTwo" and "Backdrop Two" or "Backdrop One"
    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local perEnableCheck = GUIFrame:CreateCheckbox(row1b, "Enable " .. backdropLabel, {
        value = GetCurrentBackdropDB().Enabled ~= false,
        callback = function(checked)
            GetCurrentBackdropDB().Enabled = checked
            if DBG then DBG:ApplySettings() end
            RefreshStates()
            if not checked then
                KE:SkinningReloadPrompt()
            end
        end,
    })
    row1b:AddWidget(perEnableCheck, 1)
    manager:Register(perEnableCheck, "masterOnly")
    card1:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Size Mode
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Size Mode", yOffset)
    manager:Register(card2, "all")
    local currentDB = GetCurrentBackdropDB()

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local autoSizeCheck = GUIFrame:CreateCheckbox(row2, "Auto Size to Parent Frame", {
        value = currentDB.autoSize,
        callback = function(checked, revert)
            if not checked then
                GetCurrentBackdropDB().autoSize = checked
                ApplySettings()
                RefreshStates()
                return
            end

            KE:CreatePrompt(
                "Details Override",
                "This will override your current Details sizing, are you sure you want to use this feature?",
                false, nil, false, nil, nil, nil, nil,
                function()
                    GetCurrentBackdropDB().autoSize = checked
                    ApplySettings()
                    RefreshStates()
                end,
                function()
                    revert(true)
                end,
                "Yes",
                "Cancel"
            )
        end,
    })
    row2:AddWidget(autoSizeCheck, 1)
    manager:Register(autoSizeCheck, "all")
    card2:AddRow(row2, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local detailsBarsSlider = GUIFrame:CreateSlider(row2b, "Amount of bars to show", {
        min = 1, max = 25, step = 1,
        value = currentDB.detailsBars or db.detailsBars or 7,
        callback = function(val)
            GetCurrentBackdropDB().detailsBars = val
            ApplySettings()
        end,
    })
    row2b:AddWidget(detailsBarsSlider, 0.5)
    manager:Register(detailsBarsSlider, "autoSize")

    local detailsBarHSlider = GUIFrame:CreateSlider(row2b, "Your current Details bar height", {
        min = 1, max = 50, step = 1,
        value = db.detailsBarH,
        callback = function(val)
            db.detailsBarH = val
            ApplyAll()
        end,
    })
    row2b:AddWidget(detailsBarHSlider, 0.5)
    manager:Register(detailsBarHSlider, "autoSize")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local detailsTitelHSlider = GUIFrame:CreateSlider(row2c, "Your current Details titlebar height", {
        min = 1, max = 25, step = 1,
        value = db.detailsTitelH,
        callback = function(val)
            db.detailsTitelH = val
            ApplyAll()
        end,
    })
    row2c:AddWidget(detailsTitelHSlider, 0.5)
    manager:Register(detailsTitelHSlider, "autoSize")

    local detailsSpacingSlider = GUIFrame:CreateSlider(row2c, "Your current Details spacing", {
        min = 1, max = 50, step = 1,
        value = db.detailsSpacing,
        callback = function(val)
            db.detailsSpacing = val
            ApplyAll()
        end,
    })
    row2c:AddWidget(detailsSpacingSlider, 0.5)
    manager:Register(detailsSpacingSlider, "autoSize")
    card2:AddRow(row2c, Theme.rowHeight)

    local row2d = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local detailsWidthSlider = GUIFrame:CreateSlider(row2d, "Details Width", {
        min = 50, max = 1000, step = 1,
        value = db.detailsWidth,
        callback = function(val)
            db.detailsWidth = val
            ApplyAll()
        end,
    })
    row2d:AddWidget(detailsWidthSlider, 1)
    manager:Register(detailsWidthSlider, "autoSize")
    card2:AddRow(row2d, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Backdrop Color
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Backdrop Color", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local bgColorPicker = GUIFrame:CreateColorPicker(row3a, "Backdrop Color", {
        color = GetCurrentBackdropDB().BackgroundColor,
        callback = function(r, g, b, a)
            GetCurrentBackdropDB().BackgroundColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3a:AddWidget(bgColorPicker, 1)
    manager:Register(bgColorPicker, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local borderColorPicker = GUIFrame:CreateColorPicker(row3b, "Backdrop Border Color", {
        color = GetCurrentBackdropDB().BorderColor,
        callback = function(r, g, b, a)
            GetCurrentBackdropDB().BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3b:AddWidget(borderColorPicker, 1)
    manager:Register(borderColorPicker, "all")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Position Settings (anchors gated separately on manualSize)
    ----------------------------------------------------------------
    local posOffset
    posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = GetCurrentBackdropDB(),
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 5: Manual Backdrop Size
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop Size (Manual)", yOffset)
    manager:Register(card5, "manualSize")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local backdropWidthSlider = GUIFrame:CreateSlider(row5, "Backdrop Width", {
        min = 10, max = 1000, step = 1,
        value = GetCurrentBackdropDB().width,
        callback = function(val)
            GetCurrentBackdropDB().width = val
            ApplySettings()
        end,
    })
    row5:AddWidget(backdropWidthSlider, 0.5)
    manager:Register(backdropWidthSlider, "manualSize")

    local backdropHeightSlider = GUIFrame:CreateSlider(row5, "Backdrop Height", {
        min = 10, max = 1000, step = 1,
        value = GetCurrentBackdropDB().height,
        callback = function(val)
            GetCurrentBackdropDB().height = val
            ApplySettings()
        end,
    })
    row5:AddWidget(backdropHeightSlider, 0.5)
    manager:Register(backdropHeightSlider, "manualSize")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
