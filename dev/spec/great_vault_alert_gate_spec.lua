-- Great Vault Alert's resting gate. ShouldListen is the refusal rule that
-- decides whether the four cast events are registered at all; it fails
-- toward listening when IsResting is missing or errors.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("GreatVaultAlert resting gate (Modules/QoL/GreatVaultAlert.lua)", function()
    local GVA

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/QoL/GreatVaultAlert.lua", { Print = function() end })
        GVA = modules["GreatVaultAlert"]
    end)

    it("listens only while resting, and listens when IsResting is unavailable", function()
        local cases = {
            { name = "resting",           fn = function() return true end,  want = true },
            { name = "not resting",       fn = function() return false end, want = false },
            { name = "IsResting missing",  fn = nil,                         want = true },
            { name = "IsResting erroring", fn = function() error("boom") end, want = true },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.want, GVA.ShouldListen(c.fn), c.name)
        end
    end)
end)
