-- Great Vault Alert's two refusal rules. ShouldListen decides whether the four
-- cast events are registered at all; it fails toward listening when IsResting
-- is missing or errors. IsVaultCast decides whether a cast is the vault; a
-- secret spellID never is.
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

describe("GreatVaultAlert vault-cast guard (Modules/QoL/GreatVaultAlert.lua)", function()
    local GVA
    local secretNow

    before_each(function()
        secretNow = false
        mock.install({ issecretvalue = function() return secretNow end })
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/QoL/GreatVaultAlert.lua", { Print = function() end })
        GVA = modules["GreatVaultAlert"]
    end)

    it("is the vault only for the player's plain vault spellID", function()
        -- The secret row passes the vault id itself, so only the guard can
        -- refuse it.
        local VAULT = 1271478
        local cases = {
            { name = "player, vault",        unit = "player", spellID = VAULT, secret = false, want = true },
            { name = "pet, vault",           unit = "pet",    spellID = VAULT, secret = false, want = false },
            { name = "player, other spell",  unit = "player", spellID = 12345, secret = false, want = false },
            { name = "player, secret vault", unit = "player", spellID = VAULT, secret = true,  want = false },
        }
        for _, c in ipairs(cases) do
            secretNow = c.secret
            assert.equals(c.want, GVA.IsVaultCast(c.unit, c.spellID), c.name)
        end
    end)
end)
