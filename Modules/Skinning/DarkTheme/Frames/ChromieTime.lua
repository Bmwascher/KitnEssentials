local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.ChromieTimeFrame
    if not frame then return end
    S.CloseButton(frame.CloseButton)
    S.Button(frame.SelectButton)

    S.StripTextures(frame)
    if frame.Background then frame.Background:Hide() end
    S.Template(frame, "Window")

    local title = frame.Title
    if title then
        title:DisableDrawLayer("BACKGROUND")
        S.Template(title, "Window")
    end

    local info = frame.CurrentlySelectedExpansionInfoFrame
    if info then
        info:DisableDrawLayer("BACKGROUND")
        S.Template(info, "Window")
        if info.Name then info.Name:SetTextColor(1, 0.8, 0) end
        if info.Description then info.Description:SetTextColor(1, 1, 1) end
    end
end

S:Register("Blizzard_ChromieTimeUI", Skin, "ChromieTime")
