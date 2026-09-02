-- Tier 1: a refusal rule, and the one assertion that catches it landing in the
-- wrong predicate. A hidden box must not shrink its category's count, or a
-- category with every box hidden reads as empty and goes unclickable — which
-- reports "you hid these" as "there is nothing here".
local L = require("dev.spec._ke_loader")

describe("EditMode hidden boxes", function()
    local KE, EditMode

    local function element(key, path)
        return { key = key, guiPath = path or "CombatTimer" }
    end

    before_each(function()
        KE = L.loadGlobals()
        KE.GUIFrame = {
            sidebarConfig = {
                { id = "combat_section", type = "header", items = {
                    { id = "CombatTimer" }, { id = "KickTracker" },
                } },
            },
        }
        EditMode = L.loadEditMode(KE)
        EditMode.activeCategory = nil
        EditMode.hiddenElements = {}
        EditMode.registeredElements = {
            Timer = element("Timer", "CombatTimer"),
            Kicks = element("Kicks", "KickTracker"),
        }
    end)

    it("refuses an element whose key is in the hidden set", function()
        EditMode.hiddenElements.Timer = true
        assert.is_false(EditMode:ElementShouldShow(EditMode.registeredElements.Timer))
    end)

    -- The assertion this spec exists for. It fails if the hide rule is folded
    -- into ElementIsLive instead, which is one line away and passes every other
    -- test in this file.
    it("does not change the per-category count when boxes are hidden", function()
        local before = EditMode:CountElementsInCategory("combat_section")
        EditMode.hiddenElements.Timer = true
        EditMode.hiddenElements.Kicks = true
        assert.equals(before, EditMode:CountElementsInCategory("combat_section"))
        assert.equals(2, EditMode:CountElementsInCategory("combat_section"))
    end)

    -- The same rule from the other side: liveness answers a question about the
    -- element, and hiding is not a fact about the element.
    it("leaves liveness untouched", function()
        EditMode.hiddenElements.Timer = true
        assert.is_true(EditMode:ElementIsLive(EditMode.registeredElements.Timer))
    end)
end)
