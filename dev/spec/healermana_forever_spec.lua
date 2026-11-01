-- Tier 1: Healer Mana's Forever rules (Modules/Combat/StatusTexts/HealerMana.lua):
-- another member's talent role from LibSpecialization decides when the
-- library has one, else the group role they set; a reported role rebuilds
-- the list only when it changed and the tracker is on and not previewing.
local L = require("dev.spec._ke_loader")

describe("HealerMana on Forever: healer rule", function()
    it("takes the library role when there is one, else the set role", function()
        local HM = L.loadHealerMana()
        for _, row in ipairs({
            { name = "library HEALER, set DAMAGER", library = "HEALER", assigned = "DAMAGER", want = true },
            { name = "library DAMAGER, set HEALER", library = "DAMAGER", assigned = "HEALER", want = false },
            { name = "no library, set HEALER", assigned = "HEALER", want = true },
            { name = "no library, set NONE", assigned = "NONE", want = false },
        }) do
            assert.equals(row.want, HM.ForeverIsHealer(row.library, row.assigned), row.name)
        end
    end)

    it("rebuilds the list on a changed role only while on and not previewing", function()
        local HM = L.loadHealerMana()
        for _, row in ipairs({
            { name = "changed, on", old = "DAMAGER", new = "HEALER", on = true, want = true },
            { name = "first report, on", new = "HEALER", on = true, want = true },
            { name = "unchanged, on", old = "HEALER", new = "HEALER", on = true, want = false },
            { name = "changed, off", old = "DAMAGER", new = "HEALER", on = false, want = false },
            { name = "changed, previewing", old = "DAMAGER", new = "HEALER", on = true, preview = true, want = false },
        }) do
            assert.equals(row.want, HM.ForeverRoleRefreshes(row.old, row.new, row.on, row.preview == true), row.name)
        end
    end)
end)
