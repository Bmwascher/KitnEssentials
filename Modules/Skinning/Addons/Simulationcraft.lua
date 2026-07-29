local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function SkinMainFrame()
    local f = _G.SimcFrame
    if not f or S.data(f).skinned then return end
    S.data(f).skinned = true
    S.StripTextures(f)
    S.Backdrop(f)
    if _G.SimcFrameButton then
        S.Button(_G.SimcFrameButton)
        local fo = _G.SimcFrameButton.GetNormalFontObject and _G.SimcFrameButton:GetNormalFontObject()
        if fo then S.SetFont(fo) end
    end
    if f.CheckButton then
        S.CheckBox(f.CheckButton)
        if f.CheckButton.Text then S.SetFont(f.CheckButton.Text) end
    end
    if _G.SimcScrollFrameScrollBar then S.ScrollBar(_G.SimcScrollFrameScrollBar) end
    if _G.SimcEditBox then S.SetFont(_G.SimcEditBox) end
end

local function Skin()
    local LibStub = _G.LibStub
    if not LibStub then return end
    local ok, ace = pcall(LibStub, "AceAddon-3.0")
    if not ok or not ace then return end
    local addon = ace.GetAddon and ace:GetAddon("Simulationcraft", true)
    if addon and addon.GetMainFrame then
        hooksecurefunc(addon, "GetMainFrame", SkinMainFrame)
    end
end

S:Register("Simulationcraft", Skin, "Simulationcraft")
