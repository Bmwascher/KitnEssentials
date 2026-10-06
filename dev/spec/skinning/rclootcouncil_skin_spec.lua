-- Modules/Skinning/Addons/RCLootCouncil.lua -- ensurePlan, PageDirection,
-- headerSize.
--
-- While its row is on, the skin keeps RC on the KitnUI skin-list entry. The
-- post-hook on RC's ActivateSkin asks this predicate whether to put the entry
-- back and whether to select it. Inside its own ActivateSkin call it must do
-- neither, or the hook recurses.
--
-- The page buttons' art is cleared by re-setting the normal texture to the
-- clear value, which re-enters the arrow's rotation hook. Only RC's page paths
-- may turn the arrow.

local L = require("dev.spec._ke_loader")

describe("RCLootCouncil skin-list guard", function()
    it("inserts a missing entry, selects it unless already selected, and does nothing inside its own call", function()
        local ensurePlan = L.loadRCLootCouncilSkin()
        -- present, isKitnUI, inOwnCall -> insert, activate
        local cases = {
            { false, false, false, true,  true  },
            { false, true,  false, true,  true  },
            { true,  false, false, false, true  },
            { true,  true,  false, false, false },
            { false, false, true,  false, false },
            { true,  false, true,  false, false },
        }
        for i, c in ipairs(cases) do
            local insert, activate = ensurePlan(c[1], c[2], c[3])
            assert.same({ c[4], c[5] }, { insert, activate }, "case " .. i)
        end
    end)

    it("turns the arrow only for RC's page paths, never for the clear value or another file", function()
        local _, pageDirection = L.loadRCLootCouncilSkin()
        -- texture, direction
        local cases = {
            { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", "left" },
            { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down", "right" },
            { 0, nil },
            { nil, nil },
            { "Interface\\Buttons\\UI-Panel-Button-Up", nil },
        }
        for i, c in ipairs(cases) do
            assert.equals(c[2], pageDirection(c[1]), "case " .. i)
        end
    end)

    it("keeps a size that fits, else takes the largest whole size below it that fits, else the floor, and never raises a size at or below the floor", function()
        local _, _, headerSize = L.loadRCLootCouncilSkin()
        local function fitsAtOrBelow(limit)
            return function(size) return size <= limit end
        end
        -- current size, largest size that fits, expected
        local cases = {
            { 12, 12, 12 },
            { 12, 10, 10 },
            { 12, 7, 8 },
            { 7, 6, 7 },
            { 8, 6, 8 },
        }
        for i, c in ipairs(cases) do
            assert.equals(c[3], headerSize(c[1], fitsAtOrBelow(c[2])), "case " .. i)
        end
    end)
end)
