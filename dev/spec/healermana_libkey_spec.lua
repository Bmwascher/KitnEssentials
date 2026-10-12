-- Tier 1: Healer Mana's spec lookup key
-- (Modules/Combat/StatusTexts/HealerMana.lua, HM:BuildHealerSnapshot). The
-- library files a member under name, or name-realm for another realm; the
-- lookup builds the same key, and none when the name or realm cannot be read.
local L = require("dev.spec._ke_loader")

local SECRET = {}

describe("HealerMana spec lookup key", function()
    it("finds the library's key and looks up nothing for an unreadable name or realm", function()
        local cases = {
            { name = "same realm", unitName = function() return "Healer", nil end, want = 256 },
            { name = "another realm", unitName = function() return "Healer", "Other" end, want = 257 },
            { name = "secret realm", unitName = function() return "Healer", SECRET end, want = nil },
            { name = "UnitName raises", unitName = function() error("restricted") end, want = nil },
        }
        for _, case in ipairs(cases) do
            local HM = L.loadHealerMana({
                UnitName = case.unitName,
                issecretvalue = function(v) return v == SECRET end,
            })
            HM.libSpecCache = { Healer = 256, ["Healer-Other"] = 257 }
            assert.are.equal(case.want, HM:BuildHealerSnapshot("party1").specID, case.name)
        end
    end)
end)
