-- Modules/Dungeons/LFGReminder.lua -- which role the popup draws. The
-- application role is the one the player was accepted as; the assigned role is
-- the fallback, and the only source on the leader path. An edit that swaps the
-- order or accepts "NONE" draws the wrong role with no error. The mock declares
-- nothing secret, so the secret refusal inside the pick is verified in game,
-- not here. Layout and art are smoke.
local loader = require("dev.spec._ke_loader")

describe("LFGReminder role pick", function()
    local pick

    before_each(function()
        local LR = loader.loadLFGReminder()
        pick = LR._PickRole
    end)

    it("takes the application role when it is a real role", function()
        for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
            assert.equals(role, pick(role, "NONE"), role)
        end
        assert.equals("HEALER", pick("HEALER", "TANK"), "over a different assigned role")
    end)

    it("falls back to the assigned role when the application role is missing or NONE", function()
        local cases = {
            { name = "missing", app = nil },
            { name = "NONE",    app = "NONE" },
        }
        for _, case in ipairs(cases) do
            assert.equals("TANK", pick(case.app, "TANK"), case.name)
        end
    end)

    it("gives no role when neither is usable", function()
        local cases = {
            { name = "both missing",    app = nil,      assigned = nil },
            { name = "both NONE",       app = "NONE",   assigned = "NONE" },
            { name = "unknown strings", app = "LEADER", assigned = "" },
        }
        for _, case in ipairs(cases) do
            assert.is_nil(pick(case.app, case.assigned), case.name)
        end
    end)
end)
