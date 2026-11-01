-- Tier 1: refusal rules. Whether Edit Mode draws an element's box is decided in
-- one place; a later edit that loosens any branch here silently brings back
-- boxes for modules the user switched off.
local L = require("dev.spec._ke_loader")

describe("EditMode eligibility", function()
    local KE, EditMode

    local function element(overrides)
        local e = { key = "Thing", guiPath = "CombatTimer" }
        for k, v in pairs(overrides or {}) do e[k] = v end
        return e
    end

    before_each(function()
        KE = L.loadGlobals()
        KE.GUIFrame = {
            sidebarConfig = {
                { id = "combat_section", type = "header", items = { { id = "CombatTimer" } } },
                { id = "qol_section", type = "header", items = { { id = "GreatVaultAlert" } } },
            },
        }
        EditMode = L.loadEditMode(KE)
        EditMode.activeCategory = nil
    end)

    describe("ElementIsLive", function()
        it("is live when no module and no isEligible are supplied", function()
            assert.is_true(EditMode:ElementIsLive(element()))
        end)

        it("refuses an element whose module reports disabled", function()
            local mod = { IsEnabled = function() return false end }
            assert.is_false(EditMode:ElementIsLive(element({ module = mod })))
        end)

        it("allows an element whose module reports enabled", function()
            local mod = { IsEnabled = function() return true end }
            assert.is_true(EditMode:ElementIsLive(element({ module = mod })))
        end)

        it("refuses when isEligible returns false", function()
            assert.is_false(EditMode:ElementIsLive(element({ isEligible = function() return false end })))
        end)

        it("refuses when the module is enabled but the mode is not eligible", function()
            local mod = { IsEnabled = function() return true end }
            assert.is_false(EditMode:ElementIsLive(element({
                module = mod, isEligible = function() return false end,
            })))
        end)
    end)

    describe("ElementMatchesCategory", function()
        it("matches everything when unfiltered", function()
            assert.is_true(EditMode:ElementMatchesCategory(element()))
        end)

        it("matches an element in the active category", function()
            EditMode.activeCategory = "combat_section"
            assert.is_true(EditMode:ElementMatchesCategory(element()))
        end)

        it("refuses an element outside the active category", function()
            EditMode.activeCategory = "qol_section"
            assert.is_false(EditMode:ElementMatchesCategory(element()))
        end)

        -- A module whose sidebar page has not been added yet must still reach
        -- the tool under All rather than vanishing from it entirely.
        it("refuses an unresolvable guiPath only while filtered", function()
            local orphan = element({ guiPath = "NotARealPage" })
            assert.is_true(EditMode:ElementMatchesCategory(orphan))
            EditMode.activeCategory = "combat_section"
            assert.is_false(EditMode:ElementMatchesCategory(orphan))
        end)

        -- The Healer Mana and Raid Cooldowns stack belongs to both pages, and
        -- in either category it is the only box that moves them.
        it("matches an element in its second page's category too", function()
            local both = element({ alsoGuiPath = "GreatVaultAlert" })
            EditMode.activeCategory = "qol_section"
            assert.is_true(EditMode:ElementMatchesCategory(both))
            EditMode.activeCategory = "combat_section"
            assert.is_true(EditMode:ElementMatchesCategory(both))
        end)
    end)

    describe("CountElementsInCategory", function()
        it("counts an element in its own section, and one with alsoGuiPath in both", function()
            EditMode.registeredElements = {
                Own = element({ key = "Own" }),
                Both = element({ key = "Both", alsoGuiPath = "GreatVaultAlert" }),
            }
            local cases = {
                { section = "combat_section", want = 2 },
                { section = "qol_section", want = 1 },
                { section = nil, want = 2 },
            }
            for _, c in ipairs(cases) do
                assert.are.equal(c.want, EditMode:CountElementsInCategory(c.section), tostring(c.section))
            end
        end)
    end)

    describe("ElementShouldShow", function()
        it("requires both category and liveness", function()
            local mod = { IsEnabled = function() return false end }
            EditMode.activeCategory = "combat_section"
            assert.is_false(EditMode:ElementShouldShow(element({ module = mod })))
        end)

        it("shows a live element in the active category", function()
            EditMode.activeCategory = "combat_section"
            assert.is_true(EditMode:ElementShouldShow(element()))
        end)

        it("refuses a nil element rather than erroring", function()
            assert.is_false(EditMode:ElementShouldShow(nil))
        end)
    end)
end)
