-- Tier 2: sidebar item to section resolution. Edit Mode groups its overlays by
-- the same sections the GUI groups its pages by, so the two can never disagree.
local L = require("dev.spec._ke_loader")

describe("KE:GetSectionForItem", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
        KE.GUIFrame = {
            sidebarConfig = {
                {
                    id = "combat_section",
                    type = "header",
                    items = { { id = "CombatTimer" }, { id = "HealerTools" } },
                },
                {
                    id = "dungeons_section",
                    type = "header",
                    items = { { id = "DungeonCasts" } },
                },
                { id = "settings_section", type = "header" },
            },
        }
    end)

    it("resolves a sidebar item id to its owning section", function()
        assert.equals("combat_section", KE:GetSectionForItem("CombatTimer"))
        assert.equals("dungeons_section", KE:GetSectionForItem("DungeonCasts"))
    end)

    it("resolves several items sharing one section", function()
        assert.equals("combat_section", KE:GetSectionForItem("HealerTools"))
    end)

    it("returns nil for an id the sidebar does not contain", function()
        assert.is_nil(KE:GetSectionForItem("NotARealPage"))
    end)

    it("returns nil for a nil id rather than erroring", function()
        assert.is_nil(KE:GetSectionForItem(nil))
    end)

    it("tolerates a header carrying no items", function()
        assert.is_nil(KE:GetSectionForItem("settings_section"))
    end)

    -- Hardening, not a live bug fix: the sidebar config is a file-parse literal
    -- in game, so this branch is unreachable there. It is reachable here.
    it("does not cache an empty result when the sidebar is not built yet", function()
        local fresh = L.loadGlobals()
        fresh.GUIFrame = nil
        assert.is_nil(fresh:GetSectionForItem("CombatTimer"))

        fresh.GUIFrame = {
            sidebarConfig = {
                { id = "combat_section", type = "header", items = { { id = "CombatTimer" } } },
            },
        }
        assert.equals("combat_section", fresh:GetSectionForItem("CombatTimer"))
    end)
end)
