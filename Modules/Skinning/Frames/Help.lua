local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local main = _G.HelpFrame
    if not main then return end
    S.StripTextures(main)

    local bd = S.Backdrop(main)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", main, "TOPLEFT", -8, 8)
        bd:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 8, -8)
    end
    S.CloseButton(main.CloseButton)

    if bd and main.CloseButton then
        main.CloseButton:ClearAllPoints()
        main.CloseButton:SetPoint("TOPRIGHT", bd, "TOPRIGHT", -4, -4)
    end

    local browser = _G.HelpBrowser
    if browser then
        if browser.BrowserInset then S.StripTextures(browser.BrowserInset) end

        local bbd = S.Backdrop(browser, 0, true)
        if bbd then
            bbd:ClearAllPoints()
            bbd:SetPoint("TOPLEFT", browser, "TOPLEFT", -1, 1)
            bbd:SetPoint("BOTTOMRIGHT", browser, "BOTTOMRIGHT", 1, -2)
        end
    end
end

S:RegisterEarly(Skin, "Help")
