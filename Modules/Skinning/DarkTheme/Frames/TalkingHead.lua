local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function PinAtlasNil(tex)
    if not tex then return end
    tex:SetAtlas(nil)
    local d = S.data(tex)
    if d.pinned then return end
    d.pinned = true
    hooksecurefunc(tex, "SetAtlas", function(t, atlas)
        if atlas ~= nil and not S.data(t).resetting then
            S.data(t).resetting = true
            t:SetAtlas(nil)
            S.data(t).resetting = nil
        end
    end)
end

local function PinTextColor(fs, r, g, b)
    if not fs then return end
    fs:SetTextColor(r, g, b)
    local d = S.data(fs)
    if d.pinned then return end
    d.pinned = true
    hooksecurefunc(fs, "SetTextColor", function(f, nr, ng, nb)
        if (nr ~= r or ng ~= g or nb ~= b) and not S.data(f).resetting then
            S.data(f).resetting = true
            f:SetTextColor(r, g, b)
            S.data(f).resetting = nil
        end
    end)
end

local function Skin()
    local th = _G.TalkingHeadFrame
    if not th then return end
    if S.data(th).skinned then return end

    if th.BackgroundFrame and th.BackgroundFrame.TextBackground then
        PinAtlasNil(th.BackgroundFrame.TextBackground)
    end
    if th.PortraitFrame then
        if th.PortraitFrame.Portrait then PinAtlasNil(th.PortraitFrame.Portrait) end
        S.StripTextures(th.PortraitFrame)
    end
    if th.MainFrame and th.MainFrame.Model and th.MainFrame.Model.PortraitBg then
        PinAtlasNil(th.MainFrame.Model.PortraitBg)
    end

    S.StripTextures(th)
    S.Backdrop(th)
    if th.MainFrame then
        S.StripTextures(th.MainFrame)
        local close = th.MainFrame.CloseButton
        if close then
            S.CloseButton(close)
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", th.BackgroundFrame or th, "TOPRIGHT", 0, -2)
        end
    end

    if th.NameFrame and th.NameFrame.Name then
        PinTextColor(th.NameFrame.Name, 1, 0.82, 0.02)
    end
    if th.TextFrame and th.TextFrame.Text then
        PinTextColor(th.TextFrame.Text, 1, 1, 1)
    end

    S.data(th).skinned = true
end

S:RegisterEarly(Skin, "TalkingHead")
S:Register("Blizzard_TalkingHeadUI", Skin, "TalkingHead")
