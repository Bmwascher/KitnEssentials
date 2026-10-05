local L = require("dev.spec._ke_loader")

-- Classify is the module's whole trigger rule: which events open the window,
-- which close it, and that a secret spell id is never compared.
local SECRET = { __secret = true }
local function isSecret(v) return type(v) == "table" and v.__secret == true end

describe("AlterTime.Classify", function()
    it("maps each event and spell id to start, end or nothing", function()
        local AT = L.loadAlterTime({ issecretvalue = isSecret })
        local rows = {
            { "UNIT_SPELLCAST_SUCCEEDED", 342245, "start" },
            { "UNIT_SPELLCAST_SUCCEEDED", 342247, "end" },
            { "UNIT_SPELLCAST_SUCCEEDED", 133, nil },
            { "UNIT_SPELLCAST_SUCCEEDED", SECRET, nil },
            { "PLAYER_DEAD", nil, "end" },
            { "PLAYER_ENTERING_WORLD", false, "end" },
        }
        for _, r in ipairs(rows) do
            assert.equals(r[3], AT.Classify(r[1], r[2]), r[1] .. " " .. tostring(r[2]))
        end
    end)
end)
