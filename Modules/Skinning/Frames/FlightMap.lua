local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.FlightMapFrame
    if not frame then return end
    S.Frame(frame)

end

S:Register("Blizzard_FlightMap", Skin, "FlightMap")
