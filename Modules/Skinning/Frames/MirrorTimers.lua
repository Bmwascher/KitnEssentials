local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

-- The fill is drawn slightly proud of the frame so the border reads as an
-- outline around it rather than a box inside it.
local BAR_W, BAR_H = 200, 18
local BAR_FILL_W, BAR_FILL_H = 204, 22

local function SetupTimer(container, timer)
    local bar = container.GetAvailableTimer and container:GetAvailableTimer(timer)
    if not bar then return end

    if not bar.aeAtlasHolder then
        bar.aeAtlasHolder = CreateFrame("Frame", nil, bar)
        bar.aeAtlasHolder:SetClipsChildren(true)
        bar.aeAtlasHolder:SetPoint("TOPLEFT", 1, -1)
        bar.aeAtlasHolder:SetPoint("BOTTOMRIGHT", -1, 1)

        if bar.StatusBar then
            bar.StatusBar:SetParent(bar.aeAtlasHolder)
            bar.StatusBar:ClearAllPoints()
            bar.StatusBar:SetSize(BAR_FILL_W, BAR_FILL_H)
            bar.StatusBar:SetPoint("TOP", 0, 2)
        end

        bar:SetSize(BAR_W, BAR_H)

        if bar.Text then

            S.SetFont(bar.Text, nil, "OUTLINE")
            bar.Text:ClearAllPoints()
            if bar.StatusBar then
                bar.Text:SetParent(bar.StatusBar)
                bar.Text:SetPoint("CENTER", bar.StatusBar, 0, 1)
            end
        end
    end

    S.StripTextures(bar)
    S.Backdrop(bar)
end

local function Skin()
    local container = _G.MirrorTimerContainer
    if not container or container.aeHooked then return end
    if type(container.SetupTimer) == "function" then
        hooksecurefunc(container, "SetupTimer", SetupTimer)
        container.aeHooked = true
    end
end

S:RegisterEarly(Skin, "MirrorTimers")
