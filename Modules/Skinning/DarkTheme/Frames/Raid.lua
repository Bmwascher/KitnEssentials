local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs -- luacheck: ignore 211/ipairs

local function Skin()
    local frame = _G.RaidFrame
    if frame then S.Frame(frame) end

    for g = 1, 8 do
        local group = _G["RaidGroup" .. g]
        if group then
            S.StripTextures(group)
            for j = 1, 5 do
                local slot = _G["RaidGroup" .. g .. "Slot" .. j]
                if slot then
                    S.StripTextures(slot)
                    S.Backdrop(slot, 0, true)
                end
            end
        end
    end

end

S:Register("Blizzard_RaidUI", Skin, "Raid")
