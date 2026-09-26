-- Great Vault Alert's two refusal rules. ShouldListen decides whether the four
-- cast events are registered at all; it fails toward listening when IsResting
-- is missing or errors. IsVaultCast decides whether a cast is the vault; a
-- secret unit or spellID never is.
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
    local secretValue

    before_each(function()
        secretValue = nil
        mock.install({ issecretvalue = function(v) return secretValue ~= nil and v == secretValue end })
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/QoL/GreatVaultAlert.lua", { Print = function() end })
        GVA = modules["GreatVaultAlert"]
    end)

    it("is the vault only for the player's plain unit and plain vault spellID", function()
        -- Each secret row passes the player and the vault id themselves and
        -- marks one of them secret, so only that value's guard can refuse it.
        local VAULT = 1271478
        local cases = {
            { name = "player, vault",        unit = "player", spellID = VAULT, want = true },
            { name = "pet, vault",           unit = "pet",    spellID = VAULT, want = false },
            { name = "player, other spell",  unit = "player", spellID = 12345, want = false },
            { name = "player, secret vault", unit = "player", spellID = VAULT, secret = "spellID", want = false },
            { name = "secret player, vault", unit = "player", spellID = VAULT, secret = "unit",    want = false },
        }
        for _, c in ipairs(cases) do
            secretValue = c.secret and c[c.secret] or nil
            assert.equals(c.want, GVA.IsVaultCast(c.unit, c.spellID), c.name)
        end
    end)
end)
