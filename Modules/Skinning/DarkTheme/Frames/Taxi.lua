local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.TaxiFrame
    if not frame then return S.Skip("TaxiFrame missing") end
    S.Frame(frame)

end

S:RegisterEarly(Skin, "Taxi")
