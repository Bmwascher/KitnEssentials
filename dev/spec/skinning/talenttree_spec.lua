-- Modules/Skinning/DarkTheme/Frames/TalentTree.lua -- S._TalentStateColorKey.
--
-- Picks the color a talent node's frame is painted: red for a refund error,
-- gold for maxed, gray for the locked states, green for every other known
-- state, which is drawn with the spendable art. An unknown state gets no
-- color, so the node keeps Blizzard's look.

local L = require("dev.spec._ke_loader")

local STATES = {
    Normal = 1, Gated = 2, Disabled = 3, Locked = 4, Selectable = 5,
    Maxed = 6, Invisible = 7, RefundInvalid = 8, DisplayError = 9,
}

describe("talent node state colors", function()
    it("maps each visual state to its color key, and an unknown state or a missing enum to nil", function()
        local S = L.loadTalentTree().Skins
        -- visual state, states table, expected key
        local cases = {
            { STATES.Normal, STATES, "green" },
            { STATES.Gated, STATES, "gray" },
            { STATES.Disabled, STATES, "gray" },
            { STATES.Locked, STATES, "gray" },
            { STATES.Selectable, STATES, "green" },
            { STATES.Maxed, STATES, "gold" },
            { STATES.Invisible, STATES, "green" },
            { STATES.RefundInvalid, STATES, "red" },
            { STATES.DisplayError, STATES, "red" },
            { nil, STATES, nil },
            { 99, STATES, nil },
            { STATES.Maxed, nil, nil },
        }
        for i = 1, #cases do
            local c = cases[i]
            assert.equals(c[3], S._TalentStateColorKey(c[1], c[2]), "case " .. i)
        end
    end)
end)
