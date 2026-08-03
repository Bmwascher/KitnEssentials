---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("MoveFrames", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MoveFrames
    if not db then return yOffset end

    local card = GUIFrame:CreateCard(scrollChild, "Move Frames", yOffset)

    card:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("MoveFrames")
        else
            KitnEssentials:DisableModule("MoveFrames")
            -- Disabling stops the dragging immediately, but the movable and
            -- mouse flags already written onto Blizzard frames stay until a
            -- reload, so offer one.
            KE:CreateReloadPrompt("Turning off Move Frames stops the dragging now. A UI reload fully restores Blizzard's own window behaviour.")
        end
        KE:Print("Move Frames: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return card:GetNextOffset() end

    card:AddLabel("Left-click and drag almost any Blizzard window -- character panel, map, merchant, professions and most others -- to move it anywhere on screen.")
    card:AddLabel("Positions are temporary on purpose. Every window returns to its normal spot the next time it opens.")
    card:AddLabel("Steps aside automatically if BlizzMove or MoveAnything is installed. Protected windows cannot be moved while you are in combat.")

    return card:GetNextOffset()
end)
