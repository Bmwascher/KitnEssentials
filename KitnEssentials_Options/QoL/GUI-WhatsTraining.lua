-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-WhatsTraining.lua                                   ║
-- ║  GUI: What's Training                                    ║
-- ║  Purpose: Configuration panel for What's Training.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("WhatsTraining", true)
    end
    return nil
end

GUIFrame:RegisterContent("WhatsTraining", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.WhatsTraining
    if not db then return yOffset end

    local Training = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if Training then Training:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not Training then return end
        if enabled then KitnEssentials:EnableModule("WhatsTraining")
        else KitnEssentials:DisableModule("WhatsTraining") end
    end

    local function AddBoxRow(card, label, key, tooltip)
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local box = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            tooltip = tooltip,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
            end,
        })
        row:AddWidget(box, 1)
        card:AddRow(row, Theme.rowHeightLast, 0)
        manager:Register(box, "all")
    end

    local function AddButtonRow(card, label, tooltip, onClick)
        local row = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local button = GUIFrame:CreateButton(row, label, {
            tooltip = tooltip,
            callback = onClick,
        })
        row:AddWidget(button, 0.5)
        card:AddRow(row, Theme.rowHeightLast, 0)
        manager:Register(button, "all")
        return button
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "What's Training", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
    end)
    card1:AddLabel("Lists every spell your class still has to learn, what each one costs, and whether your gold " ..
        "covers the next trainer visit. Buy from the panel at any trainer: it replaces " .. KE:Gold("Train All") ..
        " while this module is on." ..
        "\n\nPrices start from a shipped table and carry a ~ until a trainer window shows the real one. " ..
        "Nothing is bought, and nothing on your bars changes, without a click.")
    yOffset = card1:GetNextOffset()

    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Panel
    ----------------------------------------------------------------
    local cardPanel = GUIFrame:CreateCard(scrollChild, "Panel", yOffset)
    AddBoxRow(cardPanel, "Open With the Spellbook", "OpenWithBook")
    AddButtonRow(cardPanel, "Open What's Training", "You can also type /kes training.", function()
        if Training then Training:OpenPanel() end
    end)
    cardPanel:AddNote("With EllesmereUI's spellbook on, the panel does not open with the book. " ..
        "Open it from here or with /kes training.")
    cardPanel:AddNote("With the gamepad interface on, the panel does not sit beside the spellbook or a trainer, and " ..
        KE:Gold("Train All") .. " stays as you set it. The panel opened alone, the toast and the chat line still work.")
    yOffset = cardPanel:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Level-Up
    ----------------------------------------------------------------
    local cardLevel = GUIFrame:CreateCard(scrollChild, "Level-Up", yOffset)
    AddBoxRow(cardLevel, "Show the Toast", "Toast", "When a new level has spells to train.")
    AddBoxRow(cardLevel, "Print a Chat Line", "ChatLine", "When a new level has spells to train.")
    yOffset = cardLevel:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Action Bars
    ----------------------------------------------------------------
    local cardBars = GUIFrame:CreateCard(scrollChild, "Action Bars", yOffset)
    AddBoxRow(cardBars, "Put the New Ranks on My Bars", "RankSwap",
        "Shows when your bars hold a lower rank. Your bars change only when you click Update Bars.")
    yOffset = cardBars:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Saved Prices
    ----------------------------------------------------------------
    local Read = KE.Training and KE.Training.Read
    local cardPrices = GUIFrame:CreateCard(scrollChild, "Saved Prices", yOffset)
    cardPrices:AddLabel((Read and Read.Count() or 0) .. " prices read on this character.")
    AddButtonRow(cardPrices, "Forget Read Prices", "Returns every price to its ~ estimate until a trainer shows it again.",
        function()
            KE:CreatePrompt(
                "Forget Read Prices",
                "Forget every price read on this character?",
                false, nil, false, nil, nil, nil, nil,
                function()
                    if Read then Read.Forget() end
                    GUIFrame:RefreshContent()
                end,
                nil,
                "Forget",
                "Cancel"
            )
        end)
    yOffset = cardPrices:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Reset
    ----------------------------------------------------------------
    local cardReset = GUIFrame:CreateCard(scrollChild, "Reset", yOffset)
    local resetButton = AddButtonRow(cardReset, "Reset to Defaults",
        "Resets these settings. Saved prices, skipped spells and kept ranks stay.", function()
            KE:CreatePrompt(
                "Reset What's Training",
                "Reset What's Training's settings to their defaults?",
                false, nil, false, nil, nil, nil, nil,
                function()
                    if Training then Training:ResetToDefaults() end
                    GUIFrame:RefreshContent()
                end,
                nil,
                "Reset",
                "Cancel"
            )
        end)
    resetButton.text:SetTextColor(0.9, 0.2, 0.2, 1)
    yOffset = cardReset:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)

    return yOffset
end)
