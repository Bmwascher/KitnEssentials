-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MerchantPages.lua                                   ║
-- ║  GUI: Merchant Pages                                     ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           MerchantPages module.                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("MerchantPages", true)
    end
    return nil
end

GUIFrame:RegisterContent("MerchantPages", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MerchantPages
    if not db then return yOffset end

    local MP = GetModule()

    local function ApplyState(enabled)
        if not MP then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("MerchantPages")
        else KitnEssentials:DisableModule("MerchantPages") end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Merchant Pages", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
        -- The MERCHANT_ITEMS_PER_PAGE global write, the created Blizzard-named
        -- MerchantItem<N> frames, and the hooksecurefunc hooks this module
        -- installs cannot be undone (Modules/QoL/MerchantPages.lua header
        -- taint note): turning the toggle off would otherwise leave the
        -- vendor window overridden by a module that reports itself off.
        if not checked then
            KE:CreateReloadPrompt("Turning off extended vendor pages requires a UI reload to restore Blizzard's window.")
        end
        KE:Print("Merchant Pages: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteHeight = 90
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") ..
        " Widens the vendor window to show several pages at once. This " ..
        "changes Blizzard's own merchant frames, which can make some later " ..
        "tooltips stop working until you reload. Turn it off and reload if " ..
        "you see that. Skipped automatically if you run a dedicated vendor " ..
        "addon. Turning it off needs a reload.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Pages
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Pages", yOffset)

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local pagesSlider = GUIFrame:CreateSlider(row2, "Pages", {
        min = 2, max = 4, step = 1,
        value = db.Pages or 2,
        callback = function(val)
            db.Pages = val
            -- The frame count is fixed at Setup and cannot change live
            -- (Modules/QoL/MerchantPages.lua Setup ordering note) -- same
            -- reload idiom the skinning pages use for a setting that only
            -- takes effect on the next load.
            KE:CreateReloadPrompt("Changing the vendor page count requires a UI reload to take effect.")
        end,
    })
    row2:AddWidget(pagesSlider, 1)
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    return yOffset
end)
