-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ColorPicker.lua                                      ║
-- ║  GUI: Color Picker                                        ║
-- ║  Purpose: Configuration panel for the                     ║
-- ║           ColorPicker module.                             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("ColorPicker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.ColorPicker
    if not db then return yOffset end

    local card = GUIFrame:CreateCard(scrollChild, "Color Picker", yOffset)

    card:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("ColorPicker")
        else
            -- No teardown: the module stays enabled until the reload, which is
            -- also why it carries keReloadOnDisable.
            KE:CreateReloadPrompt("Turning off the color picker upgrade requires a UI reload to restore Blizzard's dialog.")
        end
        KE:Print("Color Picker: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return card:GetNextOffset() end

    card:AddNote("Adds red, green, blue and transparency boxes to Blizzard's colour picker, plus copy and paste, a class-colour button, and a title bar you can drag. Turning it off needs a reload.")
    card:AddNote("Skipped automatically if ElvUI or a dedicated colour-picker addon is loaded, since those change the same window.")

    return card:GetNextOffset()
end)
