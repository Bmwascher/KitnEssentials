-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-LootRoll.lua                                         ║
-- ║  GUI: Loot Roll                                           ║
-- ║  Purpose: Configuration panel for the                     ║
-- ║           LootRoll module.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("SkinBlizzardFramesLootRoll", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.LootRoll
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local LR = KitnEssentials:GetModule("LootRoll", true)
    local manager = GUIFrame:CreateWidgetStateManager()

    local function Apply() if LR then LR:ApplySettings() end end
    local function UpdateAllWidgetStates() manager:UpdateAll(db.Enabled ~= false) end
    local function ApplyPos()
        if not LR then return end
        LR:ApplyPosition()
        if LR.SyncMover then LR:SyncMover() end
    end

    manager:SetCondition("reposition", function() return db.Replace or db.Reposition ~= false end)
    manager:SetCondition("skin", function() return db.Skin ~= false end)
    manager:SetCondition("replace", function() return db.Replace == true end)
    manager:SetCondition("legacy", function() return not db.Replace end)

    -- Card 1: Toggle
    local card1 = GUIFrame:CreateCard(scrollChild, "Loot Roll", yOffset)

    -- Module enable lives in the card header (v3.5.183 UX standard).
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("LootRoll")
        else
            KitnEssentials:DisableModule("LootRoll")
        end
        UpdateAllWidgetStates()
    end)

    -- Disabled modules collapse to the header bar alone (v3.5.188):
    -- settings only render while the module is enabled.
    if db.Enabled == false then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    card1:AddLabel("Group loot rolls: slim replacement bars (ElvUI style), or skin and reposition Blizzard's windows.")

    -- v3.5.693: sample roll bar (fake legendary, clicks inert).
    local prow = GUIFrame:CreateRow(card1.content, 30)
    local pbtn = GUIFrame:CreateButton(prow, "Preview Roll Bar", {
        callback = function()
            local LR = KitnEssentials:GetModule("LootRoll", true)
            if LR and LR.ShowPreview then LR:ShowPreview() end
        end,
        width = 140, height = 24,
    })
    prow:AddWidget(pbtn, 1)
    -- v3.5.695: the preview spawns a SLIM bar -- only meaningful in
    -- Replace mode (Blizzard-mode rolls are Blizzard's own windows,
    -- which we cannot fake).
    manager:Register(pbtn, "replace")
    card1:AddRow(prow, 30)

    local rowRep = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local repCheck = GUIFrame:CreateCheckbox(rowRep, "Replace with Slim Bars", {
        value = db.Replace == true,
        callback = function(checked)
            db.Replace = checked
            Apply()
            UpdateAllWidgetStates()
            if not checked then
                KE:SkinningReloadPrompt() -- v3.5.548: unified close-time prompt
            end
        end,
        msgPopup = true,
        msgText = "Slim Loot Roll Bars",
    })
    rowRep:AddWidget(repCheck, 1)
    manager:Register(repCheck, "all")
    card1:AddRow(rowRep, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()


    -- Card 2: Display
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    local rowS = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local skinCheck = GUIFrame:CreateCheckbox(rowS, "Skin Roll Windows (Blizzard mode)", {
        value = db.Skin ~= false,
        callback = function(checked)
            db.Skin = checked
            Apply()
            UpdateAllWidgetStates()
        end,
    })
    rowS:AddWidget(skinCheck, 1)
    manager:Register(skinCheck, "legacy")
    card3:AddRow(rowS, Theme.rowHeight)

    -- Slim-bar geometry (replacement mode; the ElvUI values as defaults).
    local rowG1 = GUIFrame:CreateRow(card3.content, 40)
    local widthSlider = GUIFrame:CreateSlider(rowG1, "Bar Width", {
        min = 150, max = 600, step = 5, value = db.Width or 340,
        callback = function(val) db.Width = val; Apply() end
    })
    rowG1:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "replace")
    local heightSlider = GUIFrame:CreateSlider(rowG1, "Bar Height", {
        min = 14, max = 40, step = 1, value = db.Height or 22,
        callback = function(val) db.Height = val; Apply() end
    })
    rowG1:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "replace")
    card3:AddRow(rowG1, 40)

    local rowG2 = GUIFrame:CreateRow(card3.content, 40)
    local btnSlider = GUIFrame:CreateSlider(rowG2, "Button Size", {
        min = 14, max = 40, step = 1, value = db.ButtonSize or 22,
        callback = function(val) db.ButtonSize = val; Apply() end
    })
    rowG2:AddWidget(btnSlider, 0.5)
    manager:Register(btnSlider, "replace")
    local fontSlider = GUIFrame:CreateSlider(rowG2, "Name Font Size", {
        min = 8, max = 20, step = 1, value = db.NameFontSize or 13,
        callback = function(val) db.NameFontSize = val; Apply() end
    })
    rowG2:AddWidget(fontSlider, 0.5)
    manager:Register(fontSlider, "replace")
    card3:AddRow(rowG2, 40)

    local rowG3 = GUIFrame:CreateRow(card3.content, 40)
    local spacingSlider = GUIFrame:CreateSlider(rowG3, "Bar Spacing", {
        min = 0, max = 20, step = 1, value = db.Spacing or 1,
        callback = function(val) db.Spacing = val; Apply() end
    })
    rowG3:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "replace")
    card3:AddRow(rowG3, 40)

    local rowQ = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local qualityCheck = GUIFrame:CreateCheckbox(rowQ, "Item-Quality Border Colors", {
        value = db.QualityBorder ~= false,
        callback = function(checked)
            db.QualityBorder = checked
            Apply()
        end,
    })
    rowQ:AddWidget(qualityCheck, 1)
    manager:Register(qualityCheck, "skin")
    card3:AddRow(rowQ, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    -- Card 3: Position
    local card2 = GUIFrame:CreateCard(scrollChild, "Position", yOffset)
    manager:Register(card2, "all")

    local rowR = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local repoCheck = GUIFrame:CreateCheckbox(rowR, "Move Loot Rolls", {
        value = db.Reposition ~= false,
        callback = function(checked)
            db.Reposition = checked
            Apply()
            UpdateAllWidgetStates()
        end,
    })
    -- v3.5.871: "Unlock (drag to move)" removed. It was a second anchor UI
    -- competing with /kes edit on the same frame and the two disagreed about
    -- where the anchor was. Positioning is /kes edit + these offsets now.
    rowR:AddWidget(repoCheck, 1)
    manager:Register(repoCheck, "legacy")
    card2:AddRow(rowR, Theme.rowHeight)

    local rowX = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local xSlider = GUIFrame:CreateSlider(rowX, "X Offset", {
        min = -1500, max = 1500, step = 1, value = db.Position.X,
        callback = function(val) db.Position.X = val; ApplyPos() end -- ApplyPos -> SyncMover
    })
    rowX:AddWidget(xSlider, 1)
    manager:Register(xSlider, "reposition")
    card2:AddRow(rowX, Theme.rowHeight)

    local rowY = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local ySlider = GUIFrame:CreateSlider(rowY, "Y Offset", {
        min = -900, max = 900, step = 1, value = db.Position.Y,
        callback = function(val) db.Position.Y = val; ApplyPos() end
    })
    rowY:AddWidget(ySlider, 1)
    manager:Register(ySlider, "reposition")
    card2:AddRow(rowY, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()


    UpdateAllWidgetStates()

    return yOffset
end)
