-- Modules/DungeonTools/DungeonTimers/DungeonTimers.lua, KE.FormatSplitTimer:
-- the countdown string of every split-layout timer. Dungeon Timers' bars and
-- Spell Reflect both call it, so this one case covers both.
local L = require("dev.spec._ke_loader")

describe("split timer string", function()
    it("shows tenths below the threshold and whole seconds rounded up at or above it", function()
        local _, KE = L.loadDungeonTimers()
        -- seconds, threshold (nil = the 30 s default), expected
        local cases = {
            { 4.3, 5, "4.3" },
            { 5, 5, "5" },
            { 5.2, 5, "6" },
            { 29.94, nil, "29.9" },
            { 30, nil, "30" },
            { 30.2, nil, "31" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[3], KE.FormatSplitTimer(case[1], case[2]), "case " .. i)
        end
    end)
end)
