-- Tier 2 honesty boundary: this declares a value secret to verify KE's branch;
-- only an in-game smoke can prove Blizzard's runtime secret/taint behavior.
local helpers = require("dev.spec._helpers")

local function loadInspectPanelWithSpec(spec, isSecret)
    local modules = helpers.installAddonShim()
    local inventoryReads = 0

    _G.GetInspectSpecialization = function() return spec end
    _G.issecretvalue = function(value) return isSecret and value == spec end
    _G.GetInventoryItemLink = function()
        inventoryReads = inventoryReads + 1
        return nil
    end
    _G.GetInventoryItemTexture = function() return nil end
    _G.C_Timer = {}
    _G.C_Item = {}
    _G.C_TooltipInfo = {}
    _G.C_AddOns = {}

    helpers.loadModule("Modules/QoL/InspectPanel.lua", {
        Print = function() end,
    })

    local InspectPanel = modules.InspectPanel
    InspectPanel.CP = {}
    return InspectPanel, function() return inventoryReads end
end

describe("Inspect panel secret values", function()
    it("refuses the average calculation when inspect specialization is secret", function()
        local secretSpec = {}
        local InspectPanel, getInventoryReads = loadInspectPanelWithSpec(secretSpec, true)

        assert.is_nil(InspectPanel:GetInspectAverageItemLevel("target"))
        assert.equals(0, getInventoryReads())
    end)
end)
