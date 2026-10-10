local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function ScrollChild(child)
    local spellInfo = child.SpellInfo
    if not spellInfo or S.data(spellInfo).skinned then return end
    if spellInfo.Icon then S.Icon(spellInfo.Icon, true) end
    if spellInfo.IconBorder then S.KillTexture(spellInfo.IconBorder) end
    S.data(spellInfo).skinned = true
end

local function ScrollUpdate(frame)
    frame:ForEachFrame(ScrollChild)
end

local function Skin()
    local frame = _G.DeathRecapFrame
    if not frame or S.data(frame).skinned then return end
    S.StripTextures(frame)
    S.Backdrop(frame)

    if frame.CloseButton then
        frame.CloseButton:SetFrameLevel(5)
        S.Button(frame.CloseButton)
    end
    if frame.CloseXButton then S.CloseButton(frame.CloseXButton) end
    if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
    if frame.ScrollBox then hooksecurefunc(frame.ScrollBox, "Update", ScrollUpdate) end
    S.data(frame).skinned = true
end

S:Register("Blizzard_DeathRecap", Skin, "DeathRecap")
