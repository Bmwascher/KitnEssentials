-- Tier 1: refusal rules. Whether an element deserves a box is decided in one
-- place; a later edit that loosens any branch here silently brings back boxes
-- for modules the user switched off.
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

        it("allows when isEligible returns true", function()
            assert.is_true(EditMode:ElementIsLive(element({ isEligible = function() return true end })))
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

    -- No secret-value case here. The project does not test secret values, and a
    -- faked one would be caught by the type check before `issecretvalue` ever
    -- ran, so the test would pass without exercising the branch it names.
    describe("SafeInset", function()
        it("passes a plain number through", function()
            assert.equals(12, EditMode._SafeInset(12))
        end)

        it("coerces a non-number to zero", function()
            assert.equals(0, EditMode._SafeInset(nil))
            assert.equals(0, EditMode._SafeInset("12"))
            assert.equals(0, EditMode._SafeInset({}))
        end)
    end)
end)
