local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function Skin()
    local frame = _G.RuneforgeFrame
    if not frame then return end
    if frame.Title then S.SetFont(frame.Title, 22, "OUTLINE") end
    S.CloseButton(frame.CloseButton)
    if frame.CreateFrame then S.Button(frame.CreateFrame.CraftItemButton) end

    local powerFrame = frame.CraftingFrame and frame.CraftingFrame.PowerFrame
    if not powerFrame then return end

    local pageControl = powerFrame.PageControl
    if pageControl then
        S.ArrowButton(pageControl.BackwardButton, "left")
        S.ArrowButton(pageControl.ForwardButton, "right")
    end

    if powerFrame.PowerList then
        hooksecurefunc(powerFrame.PowerList, "RefreshListDisplay", function(list)
            if not list.elements then return end
            for i = 1, list:GetNumElementFrames() do
                local button = list.elements[i]
                if button and not S.data(button).skinned then
                    S.data(button).skinned = true
                    if button.Border then button.Border:SetAlpha(0) end

                    if button.CircleMask then button.CircleMask:Hide() end
                    S.Icon(button.Icon, true)
                end
            end
        end)
    end
end

S:Register("Blizzard_RuneforgeUI", Skin, "Runeforge")
