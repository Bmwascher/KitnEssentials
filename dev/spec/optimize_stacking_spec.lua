-- Modules/QoL/Optimize.lua -- the Stacking Nameplates row. The CVar is a packed
-- bitfield the engine decodes; what is tested is KE's mask built from the two
-- stack-type flags, its label, and the comparison against the row's optimal.
local L = require("dev.spec._ke_loader")

local STACKING = "nameplateStackingTypes"

local CASES = {
    { enemy = false, friendly = false, label = "None",           optimal = false },
    { enemy = true,  friendly = false, label = "Enemy Units",    optimal = true  },
    { enemy = false, friendly = true,  label = "Friendly Units", optimal = false },
    { enemy = true,  friendly = true,  label = "Both",           optimal = false },
}

local function rowOptimal(OPT)
    for _, cat in ipairs(OPT.Categories) do
        for _, entry in ipairs(cat.cvars) do
            if entry.cvar == STACKING then return entry.optimal end
        end
    end
end

local function load(c)
    local OPT, rec = L.loadOptimize()
    -- A version byte (2) then a flag byte, as the client stores it.
    rec.cvars[STACKING] = "\2A"
    rec.stackBits[1] = c.enemy
    rec.stackBits[2] = c.friendly
    return OPT
end

describe("Optimize stacking nameplates", function()
    it("labels the current value from the decoded stack types", function()
        for _, c in ipairs(CASES) do
            local OPT = load(c)
            assert.equals(c.label, OPT:GetValueLabel(STACKING, OPT:GetCurrentValue(STACKING)))
        end
    end)

    it("counts only enemy-only stacking as optimal", function()
        for _, c in ipairs(CASES) do
            local OPT = load(c)
            assert.equals(c.optimal, OPT:IsOptimal(STACKING, rowOptimal(OPT)), c.label)
        end
    end)
end)
